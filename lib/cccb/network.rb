require 'thread'

class CCCB::Client::Message
  class InvalidMEssage < Exception; end
  
  module ChannelCommands
    def process
      if self.to_channel?
        @channel = self.network.update_channel( self )
        @user = @channel[@user]
      end
    end

    def channel
      return nil unless to_channel?
      @channel
    end

    def to_channel?
      self.arguments[0].start_with? '#'
    end

    def replyto
      self.arguments[0]
    end
  end

  module CMD_PRIVMSG
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
      if self.to_channel?
        super
      else
        self.user.nick
      end
    end
  end

  module CMD_PART
    include ChannelCommands
  end

  module CMD_JOIN
    include ChannelCommands
  end

  module CMD_MODE
    include ChannelCommands
  end

  MESSAGE = %r{
    ^
    (?:
      : (?<prefix> \S+ ) \s+
    )?
    (?<command> \S+ )\s+
    (?<arguments> (?:(?!:)\S+ \s+)* )
    (?:
      : (?<message> .*? )
    )?
    (?:\r\n|\n)?
    $
  }x

  attr_accessor :network, :raw, :from, :command, :arguments, :text, :hide, :user
  def initialize(network, string)
    @network = network
    @raw = string
    @hide = false
    
    match = MESSAGE.match( string ) or raise InvalidMEssage.new(string)

    @from = match[:prefix].to_sym if match[:prefix]
    @command = match[:command].to_sym
    @arguments = match[:arguments].split /\s+/
    @text = match[:message]

    @user = CCCB::Client::User.new( self )

    const = :"CMD_#{@command}"
    if self.class.constants.include? const
      self.extend self.class.const_get( const ) 
      self.process
    end
  end

  def hide?
    @hide
  end

  def to_s
    [ @from, "#{@command} #{@arguments.join(" ")}", @text ].join(" ")
  end

end

class CCCB::Client::User
  class InvalidUser < Exception; end

  FROM_REGEX = %r{
    ^
    (?:
      (?<server> [\w.]+ )
    |
      (?<nick> [^!]+ )
      !
      (?<flag> [-~^=+] )
      (?<user> [^@]+ )
      @
      (?<host> .* )
    )
    $
  }x

  attr_reader :nick, :user, :flag, :host, :id
  attr_accessor :channels, :timestamp

  def initialize(message)
    if match = FROM_REGEX.match( message.from )
      if match[:server]
        @server = match[:server]
        @id = @nick = @user = @server
        @flag = ' '
        @host = match[:server]
      else
        @nick = match[:nick]
        @user = match[:user]
        @flag = match[:flag]
        @host = match[:host]
        @id = @nick.downcase
      end
      @channels = []
    else
      @id = :system
      @nick = :system
      @user = :""
      @flag = :""
      @host = :""
    end
    @timestamp = Time.now
  end

  def servermessage?
    !!@server
  end

end

class CCCB::Client::ChannelUser

  attr_accessor :op, :voice, :time

  def initialize(user, channel, *mode)
    @channel = channel
    @mode = {
      op: false,
      voice: false
    }
    set_mode(mode)
    self.time = Time.now

    if user.respond_to? :nick
      set_user(user)
    else
      @id = user.downcase
      @nick = user
    end
  end

  def id
    @id.nil? ? @user.id : @id
  end

  def nick
    @nick.nil? ? @user.nick : @nick
  end

  def set_user(user)
    @id = nil
    @user = user
    @user.timestamp = @timestamp unless @timestamp < @user.timestamp
    user.channels << @channel
  end

  def time=(time)
    @timestamp = time
    @user.timestamp = @timestamp unless @id.nil?
  end

  def set_mode(mode)
    mode.each { |m,s| 
      spam "Set #{m} from #{@mode[m].inspect} to #{(!!s).inspect}"
      @mode[m] = !!s 
    }
  end

  def class
    super
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

  def method_missing(sym, *args)
    @user.send( sym, *args )
  end

end

class CCCB::Client::Channel

  attr_accessor :name
  
  def initialize(name, *users)
    @name = name
    @users = {}
    users.each { |u| add_user u }
  end

  def [](user)
    if user.respond_to? :nick
      @users[user.id]
    else
      @users[user.downcase]
    end
  end

  def add_user(user)
    if user.respond_to? :nick
      id = user.id
    else
      id = user.downcase
    end
    unless @users.include? id
      spam "#{self} Link #{user}"
      @users[id] = CCCB::Client::ChannelUser.new(user,self)
    end
    if user.respond_to? :host and not @users[id].respond_to? :host
      spam "#{self} Update #{id} to link to real user #{user}"
      @users[id].set_user(user)
    end
  end

  def remove_user(user)
    spam "#{self} Unlink #{user}"
    @users.delete( user.id ).channels.delete( self )
  end

  def set_mode(user, *mode)
    spam "#{self} Set mode on #{user} to #{mode}"
    @users[user].set_mode *mode
  end

  def to_s
    @name
  end
end

class CCCB::Client::Network
  include CCCB::Util::Config

  attr_reader :queue

  def configure(conf)
    @queue = Queue.new
    @client = CCCB::Client.instance
    @actors = {}
    @pending = ""
    @channels = {}

    {
      name: conf[:name],
      state: :disconnected,
      sock: nil,
      nick: conf[:nick] || @client.nick,
      user: conf[:user] || @client.user,
      host: conf[:host] || 'irc',
      port: conf[:port] || 6667,
      pass: conf[:pass] || nil,
      channels: conf[:channels] || [],
      throttle: {
        line_buffer_max: 9,
        line_rate: 0.6,
        byte_buffer_max: 1024,
        byte_rate: 128
      }
    }
  end

  def channel(name)
    @channels[name]
  end

  def update_channel( message )
    name = message.replyto.downcase
    unless @channels.include? name
      @channels[name] = CCCB::Client::Channel.new( message.replyto, message.user )
    else
      @channels[name].add_user( message.user )
    end
    @channels[name]
  end

  def receiver
    debug "Receiver starting for #{self} in state #{self.state}"
    case state
    when :disconnected
      @queue.clear
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
          schedule_hook :message, CCCB::Client::Message.new(self, line )
        else
          verbose "Disconnected from server #{host}:#{port}"
          self.sock = nil
          self.state = :disconnected
          schedule_hook :disconnected, self
          return
        end
      end
    end
  rescue Exception => e
    puts "Exception #{e}"
    debug "Exception in receiver: #{e}"
    self.state = :disconnected
    raise e
  end

  def write(data)
    @queue << data
  end

  def puts(data)
    write data.gsub(/\n/,"") + "\n"
  end

  def to_s
    "#{self.name}"
  end

  def sender
    verbose "Sender thread #{self} #{self.sock.inspect} #{self.host}:#{self.port} waiting for connection"
    sleep 1 while self.state == :disconnected
    verbose "Sender thread #{self} #{self.sock.inspect} #{self.host}:#{self.port} processing queue"

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

  def user(from)
  end

end


