require 'delegate'
require 'thread'

module Array::Printable
  attr_accessor :join_string

  def to_s
    join( (@join_string||=" ") )
  end
end

class CCCB::Message 
  class InvalidMessage < Exception; end

  module ChannelCommands
    attr_reader :replyto, :channel, :channeluser

    def process
      if arguments.empty?
        self.arguments = text.split /\s+/
      end

      @replyto = arguments[0]

      if to_channel?
        @channel = CCCB::Channel.new(self, @restore_from_archive)
        @channel_name = @channel.name
        @channeluser = @channel[self.user]
      end
    end

    def to_channel?
      @replyto.start_with? '#'
    end

  end

  module ConversationMessage
    include ChannelCommands

    CTCP_REGEX = %r{
      ^ \s* 
      \001
      (?<command>\w+)
      \s+
      (?<params>.*?)
      \001
      \s*
    $}x

    attr_reader :type, :ctcp, :ctcp_params

    def process
      if ctcp = CTCP_REGEX.match( @text )
        @ctcp = ctcp[:command].upcase.to_sym
        @ctcp_params = ctcp[:params].split(/\s+/)
        @type = :CTCP
      else
        @ctcp = false
        @type = :MSG
      end

      super
    end

    def ctcp?
      !!@ctcp
    end

    def replyto
      if to_channel?
        super
      else
        user.nick
      end
    end
  end

  module NickPlusChannel
    include ChannelCommands
    def process
      self.arguments.shift
      super
    end
  end

  module CMD_PRIVMSG
    include ConversationMessage
  end

  module CMD_NOTICE
    include ConversationMessage
  end

  module CMD_PART
    include ChannelCommands
    def process
      super
      channel.remove_user(user) unless @restore_from_archive
    end
  end

  module CMD_QUIT
    attr_reader :channels_removed
    def process
      return if @restore_from_archive

      @channels_removed = []
      user.channels.each do |c|
        @channels_removed << c
        c.remove_user(user)
        schedule_hook :user_quit, self, c
      end
      network.users.delete user
    end
  end

  module CMD_433
    def process
      return if @restore_from_archive
      error "#{network} Nick is already in use. Disconnect"
      network.disconnect
    end
  end

  module CMD_315
    include NickPlusChannel
  end

  module CMD_352
    include NickPlusChannel
    def process
      (mynick, chan, user, host, server, name, mode) = arguments
      set_user_data ":#{name}!#{user}@#{host} NULL"

      super
      
      return if @restore_from_archive
      { op: '@', voice: '+' }.each do |m,c|
        @channeluser.set_mode( m => mode[c] )
      end
    end
  end
  
  module CMD_PING
    def process
      return if @restore_from_archive
      network.puts "PONG :#{text}"
    end
  end

  module CMD_JOIN
    include ChannelCommands
    def process
      super
      return if @restore_from_archive
      if user.id == network.nick
        network.user ||= user
        network.puts "WHO #{channel}"
      end
    end
  end

  module CMD_NICK
    attr_reader :old_nick
    def process
      if arguments.empty? 
        self.arguments = text.split(/\s+/)
      end
      @old_nick = user.nick
      return if @restore_from_archive
      user.rename arguments[0]
    end
  end

  module CMD_MODE
    include ChannelCommands
    def process
      super
      return if @restore_from_archive
      if to_channel?
        pattern = arguments[1].each_char
        mode = '+'
        arguments[2,arguments.length].each do |nick|
          case ch = pattern.next
          when '+', '-'
            mode = ch
            redo
          when 'o'
            channel[nick].set_mode op: !!(mode=='+')
          when 'v'
            channel[nick].set_mode voice: !!(mode=='+')
          end
        end
      end
    end
  end

  MESSAGE = %r{
    ^
    (?:
      : (?<prefix> \S+ ) \s+
    )?
    (?<command> \S+ )
    (?:
      \s+
      (?<arguments> (?:(?!:)\S+ \s+)* )
      (?:
        : (?<message> .*? )
      )?
      (?:\r\n|\n)?
    )?
    $
  }x

  attr_accessor :network, :raw, :from, :command, :arguments, 
                :text, :hide, :user, :log_format, :command_downcase

  def initialize(network, string, restore_from_archive = false)
    @restore_from_archive = restore_from_archive
    @network = network
    @log_format = "%(network) %(raw)"
    @raw = string
    @hide = false
    
    match = set_user_data(string)

    @command = match[:command].to_sym
    @command_downcase = match[:command].downcase.to_sym
    @arguments = match[:arguments].split /\s+/
    @arguments ||= []
    @arguments.extend Array::Printable
    @text = match[:message]

    const = :"CMD_#{@command}"
    if self.class.constants.include? const
      self.extend self.class.const_get( const ) 
      process
    end
  end

  def set_user_data(string)
    debug "Patch user to #{string}" unless self.user.nil?
    match = MESSAGE.match( string ) or raise InvalidMessage.new(string)

    @from = match[:prefix] ? match[:prefix].to_sym : ""
    @user = CCCB::User.new( self, @restore_from_archive )
    match
  end

  def hide?
    @hide
  end

  def to_s
    [ @from, "#{@command} #{@arguments}", @text ].join(" ")
  end
  alias_method :to_str, :to_s

  def inspect
    "<Message:#{self.network} #{command} #{raw.inspect}>"
  end

  def nick
    self.user.nick
  end

  def format(format_string)
    format_string.keyreplace { |key|
      self.send(key).to_s || ""
    }
  end
  
  def log
    info format(@log_format)
  end

  def method_missing(sym, *args)
    if sym.to_s =~ /^arg(\d+)$/
      number = $1.to_i
      self.class.instance_exec do 
        define_method sym do
          arguments[number]
        end
      end
      self.send(sym,*args)
    else
      super
    end
  end

  def encode_with(coder)
    coder.tag = "tag:cccb9:message"
    coder.scalar = "#{network.name}: #{raw}"
  end

  YAML.add_domain_type "cccb9", "message" do |tag, data|
    if data =~ /^(.*?): (.*)$/
      network_name = $1
      string = $2
      if network = CCCB.instance.networking.networks[network_name]
        CCCB::Message.new( network, string, true )
      else
        OpenStruct.new()
      end
    end
  end
end


class CCCB::User
  class InvalidUser < Exception; end

  FROM_REGEX = %r{
    ^
    (?:
      (?<id> [^!@]+ )
    |
      (?<id> [^!]+ )
      !
      (?<flag> [-~^=+] )?
      (?<user> [^@]+ )
      @
      (?<host> .* )
    )
    $
  }x

  attr_reader :nick, :user, :flag, :host, :id, :network, :history, :from

  def self.new(message, restore_from_archive = false)
    if match = FROM_REGEX.match( message.from )
      id = match[:id].downcase
      if user = message.network.users[id]
        unless restore_from_archive
          spam "Update user #{id}"
          user.update( message, match )
        end
        user
      else
        debug "New user #{id}"
        message.network.users[id] = super(message, match)
      end
    else
      nil
    end
  end

  def update(message, match)
    spam "Update user #{match[:id]}"
    @from = message.from
    @id ||= match[:id].downcase
    @nick ||= match[:id]
    @flag = match[:flag]
    @username = match[:user]
    @hostname = match[:host]
    @history << message
    if @history.length > 10
      @history.shift
    end
  end

  def initialize(message,match, restore_from_archive = false)
    @network = message.network
    debug "Create user #{match[:id]}"
    @history = []
    update(message,match)
  end

  def system?
    @username.nil?
  end

  def to_s
    system? ? "-#{id}-" : "<#{nick}>"
  end
  alias_method :to_str, :to_s

  def rename(new_name)
    new_id = new_name.downcase
    @network.users[new_id] = self.network.users.delete(@id)
    @nick = new_name
    @id = new_name.downcase
  end

  def real
    self
  end

  def channels
    @network.channels.values.select do |c|
      c[self]
    end
  end

  def inspect
    "<User:#{@network}[#{self}]>"
  end

  def encode_with(coder)
    coder.tag = "tag:cccb9:user"
    coder.scalar = "#{network.name}: #{nick}"
  end

  YAML.add_domain_type( "cccb9", "user" ) do |tag, data|
    if data =~ /^(.*?): (.*)$/
      network_name = $1
      nick = $2
      if network = CCCB.instance.networking.networks[network_name]
         network.users[nick]
      end
    end
  end

end


class CCCB::ChannelUser 

  attr_accessor :op, :voice, :channel, :user

  def initialize(user, channel, *mode)
    @user = user
    @channel = channel
    @mode = {
      op: false,
      voice: false
    }
    set_mode(mode)
  end

  def set_mode(mode)
    mode.each { |m,s| 
      spam "Set #{m} from #{@mode[m].inspect} to #{(!!s).inspect}"
      @mode[m] = !!s 
    }
  end

  def is_op?
    @mode[:op]
  end

  def is_voice?
    is_op? or @mode[:voice]
  end

  def to_s
    "<#{ is_op? ? '@' : ( is_voice? ? '+' : ' ' ) }#{nick}>"
  end
  alias_method :to_str, :to_s

  def real
    @user
  end

  def method_missing(sym, *args)
    @user.send( sym, *args )
  end

end

class CCCB::Channel 
  include Enumerable

  attr_reader :name, :users, :network
  
  def self.new(message, restore_from_archive = false) 
    id = message.replyto.downcase
    spam "Examine #{id} and #{message.network.channels.keys}"
    if channel = message.network.channels[id]
      unless restore_from_archive or message.user.system? or channel[message.user]  
        channel.add_user message.user
      end
      channel
    else
      message.network.channels[id] = super(message)
    end
  end

  def initialize(message, restore_from_archive = false)
    info "INIT channel from #{message.inspect}"
    @network = message.network
    @name = message.replyto
    @users = {}
    debug "New channel #{name}"
    unless message.user.system? or restore_from_archive
      add_user(message.user)
    end
  end

  def [](user)
    @users[user.real]
  end

  def each(*args,&block)
    @users.each(*args, &block)
  end
  
  def by_name(nick)
    id = nick.downcase
    @users.values.find { |u| u.id == id }
  end

  def add_user(user)
    debug "Add user #{user} to #{self} " #caller: #{caller_locations}"
    @users[user.real] = CCCB::ChannelUser.new(user, self)
  end

  def remove_user(user)
    debug "#{self} Unlink #{user}"
    @users.delete( user.real )
  end

  def set_mode(user, *mode)
    debug "#{self} Set mode on #{user} to #{mode}"
    @users[user.real].set_mode *mode
  end

  def inspect
    "<Channel:#{@network}[#{self}]::#{self}:USERS=#{@users.values.map(&:nick).inspect}>"
  end

  def to_s
    @name
  end
  alias_method :to_str, :to_s

  def encode_with(coder)
    coder.tag = "tag:cccb9:channel"
    coder.scalar = "#{network.name}: #{name}"
  end

  YAML.add_domain_type( "cccb9", "channel" ) do |tag, data|
    if data =~ /^(.*?): (.*)$/
      network_name = $1
      channel = $2
      if network = CCCB.instance.networking.networks[network_name]
         network.channels[channel]
      end
    end
  end

end

class CCCB::Network 
  include CCCB::Config

  BACKOFF = {
    0 => 10,
    10 => 30,
    30 => 60,
    60 => 180,
    180 => 300,
    300 => 300
  }

  attr_reader :queue, :users, :channels, :network

  def configure(conf)
    @network = self
    @pending = ""

    @queue = Queue.new
    @client = CCCB.instance

    @channels = {}
    @users = {}

    @throttle_connections = {
      delay: 0,
      time: Time.now.to_f
    }

    {
      name: conf[:name],
      state: :disconnected,
      sock: nil,
      nick: conf[:nick] || @client.nick,
      user: conf[:user] || @client.user,
      host: conf[:host] || 'irc',
      port: conf[:port] || 6667,
      pass: conf[:pass] || nil,
      auto_join_channels: conf[:channels] || [],
      throttle: {
        line_buffer_max: 9,
        line_rate: 0.6,
        byte_buffer_max: 1024,
        byte_rate: 128
      }
    }
  end

  def inspect
    "<Network:#{self}:CHAN=#{self.channels.keys.inspect};USERS=#{self.users.values.map(&:to_s).inspect}>"
  end

  def disconnect
    self.state = :disconnected
    error "#{self} Disconnecting" 
  end

  def receiver
    spam "Receiver starting for #{self} in state #{self.state}"
    case state
    when :disconnected
      @queue.clear
      @throttle_connections[:time] = Time.now.to_f
      if @throttle_connections[:delay] > 0
        warning "#{self} Throttling connections to #{self.host}:#{self.port}: for #{@throttle_connections[:delay]}s: Reconnecting too fast"
        sleep @throttle_connections[:delay]
      end
      verbose "#{self} Connecting to #{self.host}:#{self.port}"
      self.sock = TCPSocket.open( self.host, self.port )
      self.state = :pre_login
      schedule_hook :connecting, self
    when :pre_login
      write "USER #{self.user} 0 * :#{@client.userstring}\n"
      write "PASS #{self.pass}\n" unless self.pass.nil?
      write "NICK #{self.nick}\n"
      self.state = :connected
      schedule_hook :connected, self
    when :connected
      loop do
        if line = self.sock.gets
          begin
            # IRC protocol actually is dealt with from CCCB::Message.new
            spam "RAW #{line}"
            schedule_hook :server_message, CCCB::Message.new(self, line )
          rescue Exception => e
            error "Unable to parse line: #{line}\nException: #{e}\n#{e.backtrace.inspect}"
          end
        else
          verbose "Disconnected from server #{host}:#{port}"
          if @throttle_connections[:time] - Time.now.to_f < 60
            @throttle_connections[:delay] = BACKOFF[@throttle_connections[:delay]] || 30
          else
            @throttle_connections[:delay] = 0
          end
          self.sock = nil
          self.state = :disconnected
          schedule_hook :disconnected, self
          return
        end
      end
    end
  rescue Exception => e
    debug "Receiver: #{e.class} #{e}"
    self.state = :disconnected
    raise e
  end

  def write(data)
    @queue << data
  end

  def puts(data)
    write data.gsub(/\n/,"") + "\n"
  end

  def msg(target, lines)
    Array(lines).each do |string|
      puts "PRIVMSG #{target} :#{string}"
    end
  end

  def to_s
    "#{self.name}"
  end

  def sender
    spam "Sender thread #{self} #{self.sock.inspect} #{self.host}:#{self.port} waiting for connection"
    sleep 1 while self.state == :disconnected
    debug "Sender thread #{self} #{self.sock.inspect} #{self.host}:#{self.port} processing queue"

    @byte_buffer ||= self.throttle[:byte_buffer_max]
    @line_buffer ||= self.throttle[:line_buffer_max]
    @checkpoint = Time.now.to_f
    @pending

    while lines = @queue.pop
      @pending += lines
      until (end_of_line = @pending.index("\n")).nil?
        line = @pending[0, end_of_line+1]
        @pending[0,end_of_line+1] = ""

        while line.length > 0
          if self.state == :disconnected
            debug "Sender thread terminating: #{self} is disconnected"
            return
          end
          update = Time.now.to_f
          @byte_buffer += self.throttle[:byte_rate] * ( update - @checkpoint )
          @byte_buffer = self.throttle[:byte_buffer_max] if @byte_buffer > self.throttle[:byte_buffer_max]
          @line_buffer += self.throttle[:line_rate] * ( update - @checkpoint )
          @line_buffer = self.throttle[:line_buffer_max] if @line_buffer > self.throttle[:line_buffer_max]
          @checkpoint = update
          if @line_buffer < 1 or @byte_buffer < 1
            spam "Blocking sender thread waiting for buffer replenishment. Line: #{sprintf("%.2f",@line_buffer)}, Byte: #{sprintf("%.2f", @byte_buffer)}"
            sleep 0.2
            redo
          end

          chunk = line[0,@byte_buffer]
          line[0,@byte_buffer] = ""
        
          spam "#{self.name} SEND #{chunk}"
          self.sock.write( chunk )
          @line_buffer -= 1
          @byte_buffer -= chunk.length

        end
      end
    end

  rescue Exception => e
    @config[:state] = :disconnected
    raise e
  end

  def encode_with(coder)
    coder.tag = "tag:cccb9:network"
    coder.scalar = self.name
  end

  YAML.add_domain_type( "cccb9", "network" ) do |tag, name|
    CCCB.instance.networking.networks[name] || nil
  end
end

