require 'thread'

module Array::Printable
  attr_accessor :join_string

  def to_s
    join( (@join_string||=" ") )
  end
end

module CCCB::Formattable
  def format(format_string, uri_escape: false)
    format_string.keyreplace { |key|
      str = self.send(key).to_s || ""
      if uri_escape
        URI.escape(str, "&?/=#")
      else
        str
      end
    }
  end
end

class CCCB::Message 
  include CCCB::Formattable
  class InvalidMessage < Exception; end

  module BasicMessage
    def to_channel?
      false
    end
  end
  module ChannelCommands
    attr_reader :channel, :channeluser

    def process
      if arguments.empty?
        self.arguments = text.split /\s+/
      end

      if arguments[0].start_with? '#'
        @channel = CCCB::Channel.new(arguments[0], self, @restore_from_archive)
        @channel_name = @channel.name
        @channeluser = @channel[self.user]
        @replyto = @channel
      else 
        @channel = nil
      end
    end

    def to_channel?
      !!@channel
    end

    def replyto
      if @channel
        @channel
      else
        @user
      end
    end
  end

  module ConversationMessage
    include ChannelCommands

    CTCP_REGEX = %r{
      ^ \s* 
      \001
      (?<command>\w+)
      (?:
        \s+
        (?<params>.*?)
      )?
      \001
      \s*
    $}x

    attr_reader :type, :ctcp, :ctcp_params, :ctcp_text

    def process
      if ctcp = CTCP_REGEX.match( @text )
        @ctcp = ctcp[:command].upcase.to_sym
        @ctcp_params = (ctcp[:params]||"").split(/\s+/)
        @ctcp_text = ctcp[:params]
        @type = :CTCP
      else
        @ctcp = false
        @type = :MSG
      end

      super
      if @channel_name
        self.user.channel_history[@channel_name] = self
      end
    end

    def ctcp?
      !!@ctcp
    end

    def replyto
      if to_channel?
        super
      else
        @user
      end
    end

    def write(string)
      if ctcp? and ctcp != :ACTION
        network.msg "NOTICE #{replyto} :\001#{ctcp} #{string}\001"
      else
        if string =~ /^\s*\/me\s+(.*)$/i
          string = "\001ACTION #{$~[1]}\001"
        end
        #replyto.msg caller_locations.inspect
        replyto.msg string
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

  module CMD_001
    def process
      info "Connection established to #{self.network}"
      schedule_hook :connected, self.network
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

  module CMD_NOP
    include ChannelCommands
  end

  module CMD_INT_CREATE_CHANNEL
    include ChannelCommands
  end

  module CMD_330
    def process

      (bot_name, requester, nickserv_account) = arguments
      if network.get_setting("options","accept_nickserv")
        info "This network uses nickserv. Logging registered account"
        requested_user = network.get_user(requester)
        info "Updating #{requested_user.inspect}"
        requested_user.set_setting true, "session", "authenticated"
        requested_user.set_setting true, "identity", "registered"
        requested_user.set_setting nickserv_account, "session", "nickserv_account"
      end
    end
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
      
      old_user = user
      set_user_data ":#{arguments[0]}!#{old_user.username}@#{old_user.host} NULL"
      old_user.transient_storage.each do |k,v|
        value = old_user.transient_storage.delete(k)
        next if k == 'authenticated'
        user.transient_storage[k] = value
      end
      old_user.channels.each do |channel|
        channel.remove_user(old_user)
        channel.add_user(user)
      end
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
            channel.user_by_name(nick).set_mode op: !!(mode=='+')
          when 'v'
            channel.user_by_name(nick).set_mode voice: !!(mode=='+')
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
      (?<arguments> (?: (?!:)\S+\s+)* )
      (?:
        : (?<message> .*? )
      )?
      (?:\r\n|\n)?
    )?
    $
  }x

  attr_accessor :network, :raw, :from, :command, :arguments, 
                :text, :hide, :user, :log_format, :command_downcase, 
                :time, :params

  def initialize(network, string, restore_from_archive = false)
    @restore_from_archive = restore_from_archive
    @network = network
    @log_format = "%(network) %(raw)"
    @raw = string
    @hide = false
    @time = Time.now
    
    match = set_user_data(string)

    @command = match[:command].to_sym
    @command_downcase = match[:command].downcase.to_sym
    @arguments = match[:arguments].split /\s+/ if match[:arguments]
    @arguments ||= []
    @arguments.extend Array::Printable
    @text = match[:message].to_s
    @params = @arguments + @text.to_s.split(/\s+/)
    @params.extend Array::Printable

    const = :"CMD_#{@command}"
    self.extend BasicMessage
    if self.class.constants.include? const
      self.extend self.class.const_get( const ) 
      process
    end
  end

  def reply(data = nil)
    @response ||= CCCB::Reply.new(self)
    unless data.nil?
      @response.summary = data 
      send_reply
    else
      @response
    end
  end

  def send_reply(final = false)
    unless @response.nil?
      data = @response.minimal_form
      CCCB.instance.reply.irc_parser.render(data).split(/\n/).each do |l|
        self.write l
      end
      @response = nil
    end
  end

  def clear_reply
    @response = nil
  end

  def name
    user.nick
  end

  def set_user_data(string)
    spam "Patch user to #{string}" unless self.user.nil?
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

  def nick_with_mode
    if self.channeluser
      self.channeluser.nick_with_mode
    else 
      nick
    end
  end

  def log
    info format(@log_format)
  end

  def channel
    raise "Not a channel"
  end

  def method_missing(sym, *args)
    if sym.to_s =~ /^arg(?<from>\d+)(?:to(?<to>\d+|N))?$/
      from = ($~[:from] || 0).to_i
      to = if $~[:to] == "N"
        @params.count
      elsif $~[:to]
        $~[:to].to_i
      else
        from
      end
      range = Range.new( from, to )
      self.class.instance_exec do 
        define_method sym do
          @params[range].join(" ")
        end
      end
      self.send(sym,*args)
    else
      begin
        super
      rescue Exception => e
        p e, e.backtrace
      end
    end
  end

  def encode_with(coder)
    coder.tag = "tag:cccb9:message"
    coder.scalar = "#{network.name}: t#{@time.utc.to_f} #{raw}"
  end

  YAML.add_domain_type "cccb9", "message" do |tag, data|
    if data =~ /^(.*?): (\d+\.\d+) (\w+) (.*)$/
      network_name = $1
      time = $2
      tz = $3
      string = $4
      if network = CCCB.instance.networking.networks[network_name]
        CCCB::Message.new( network, string, true )
      else
        OpenStruct.new()
      end
    elsif data =~ /^(.*?): (.*)$/
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
  include CCCB::Formattable
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

  attr_reader :nick, :username, :flag, :host, :id, :network, :history, :from, :channel_history

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
        verbose "New user #{id}"
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
    @channel_history ||= {}
    @history << message
    if @history.length > 10
      @history.shift
    end
  end

  def initialize(message,match, restore_from_archive = false)
    @network = message.network
    verbose "Create user #{match[:id]}"
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

  def name
    nick
  end

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

  def msg(data)
    network.msg(self.nick,data)
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
  include CCCB::Formattable

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

  def nick_with_mode
    "#{ is_op? ? '@' : ( is_voice? ? '+' : ' ' ) }#{nick}"
  end

  def name
    user.nick
  end

  def to_s
    "<#{nick_with_mode}>"
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
  include CCCB::Formattable
  include Enumerable

  attr_reader :name, :users, :network
  alias_method :channel, :name
  
  def self.new(name, message, restore_from_archive = false) 
    id = name.downcase
    spam "Examine #{id} and #{message.network.channels.keys}"
    if channel = message.network.channels[id]
      unless restore_from_archive or message.user.system? or channel[message.user]  
        channel.add_user message.user
      end
      channel
    else
      message.network.channels[id] = super(id,message,restore_from_archive)
    end
  end

  def initialize(name, message, restore_from_archive = false)
    debug "INIT channel from #{message.inspect}"
    @network = message.network
    @name = name
    @users = {}
    verbose "New channel #{name}"
    unless message.user.system? or restore_from_archive
      add_user(message.user)
    end
  end

  def msg(data)
    network.msg(self,data)
  end

  def notice(data)
    network.notice(self,data)
  end

  def id
    @name
  end

  def [](user)
    @users[user.real]
  end

  def each(*args,&block)
    @users.each(*args, &block)
  end
  
  def user_by_name(nick)
    id = nick.to_s.downcase
    @users.values.find { |u| 
      u.id == id 
    }
  end

  def nick_with_mode
    user_by_name( network.nick ).nick_with_mode
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
    verbose "#{self} Set mode on #{user} to #{mode}"
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
  include CCCB::Formattable
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
      username: conf[:user] || @client.user,
      host: conf[:host] || 'irc',
      port: conf[:port] || 6667,
      pass: conf[:pass] || nil,
      auto_join_channels: conf[:channels] || [],
      throttle: {
        line_buffer_max: 9,
        line_rate: 0.9,
        byte_buffer_max: 1024,
        byte_rate: 128
      }
    }
  end

  def user
    get_user(self.nick)
  end

  def get_user(name, autovivify: true)
    id = name.downcase
    if users.include? id
      users[id]
    elsif autovivify
      # autovivify!
      CCCB::Message.new( self, ":#{name}!nil@nil NOOP :", true ).user
    else
      nil
    end
  end

  def get_channel(name)
    id = name.downcase
    if channels.include? id
      channels[id]
    else
      CCCB::Message.new( self, ":internal INT_CREATE_CHANNEL #{name} :", true ).channel
    end
  end

  def inspect
    "<Network:#{self}>"
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
      puts "USER #{self.username} 0 * :#{@client.userstring}"
      puts "PASS #{self.pass}" unless self.pass.nil?
      puts "NICK #{self.nick}"
      self.state = :login
      schedule_hook :login, self
    when :connected, :login
      loop do
        
        line = nil
        begin
          Timeout.timeout(300) do
            line = self.sock.gets
          end
        rescue Timeout::Error
          puts "ISON #{self.nick}"
          retry
        end

        if line
          begin
            line.force_encoding("UTF-8")
            # IRC protocol actually is dealt with from CCCB::Message.new
            spam "RAW #{line}"
            schedule_hook :server_message, CCCB::Message.new(self, line )
          rescue Exception => e
            error "Unable to parse line: #{line}\nException: #{e.message}\n#{e.backtrace.inspect}"
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

  def connected?
    self.state == :connected
  end

  def write(data)
    @queue << data
  end

  def puts(data)
    write data + "\r\n"
    schedule_hook :server_send, self, data
  end

  def notice(target, lines)
    Array(lines).each do |string|
      puts "NOTICE #{target} :#{string}"
      schedule_hook :client_notice, self, target, string
    end
  end

  def msg(target, lines)
    strings = Array(lines).each_with_object([]) do |line,a|
      next if line.nil?
      while line.length > 420
        chunk = line.slice(0,420)
        if index = chunk.rindex(' ')
          a << chunk[0,index]
          line[0,index+1] = ""
        else
          a << chunk
          line[0,420] = ""
        end
      end
      a << line
    end
    strings.each do |string|
      puts "PRIVMSG #{target} :#{string}"
      schedule_hook :client_privmsg, self, target, string
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
          schedule_hook :server_lowlevel_write, self, chunk
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

