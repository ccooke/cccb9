
module Array::Printable
  attr_accessor :join_string

  def extended(into)
    into.instance_variable_set( :@join_string, " " )
  end

  def to_s
    self.join( @join_string  )
  end
end

class CCCB::Message
  class InvalidMEssage < Exception; end
  
  module ChannelCommands
    def process
      if self.arguments.empty?
        self.arguments = self.text.split /\s+/
      end

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
      if self.to_channel?
        super
      else
        self.user.nick
      end
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
      self.channel.remove_user(self.user)
    end
  end

  module CMD_JOIN
    include ChannelCommands
    def process
      super
      self.channel.add_user(self.user)
    end
  end

  module CMD_MODE
    include ChannelCommands
    def process
      super
      if self.to_channel?
        pattern = self.arguments[1].each_char
        mode = '+'
        self.arguments[2,self.arguments.length].each do |nick|
          case ch = pattern.next
          when '+', '-'
            mode = ch
            redo
          when 'o'
            self.channel[nick].set_mode op: !!(mode=='+')
          when 'v'
            self.channel[nick].set_mode voice: !!(mode=='+')
          end
        end
      end
    end
  end

  module CMD_353
    include ChannelCommands
    attr_reader :names_target, :channel_type

    def process
      @names_target = self.arguments.shift # bot nick
      @channel_type = self.arguments.shift # char, [=@+]
      super
      
      self.text.split(/\s+/).each do |user|
        if user =~ /^ (?: (?<op> [@] ) | (?<voice> [+] ) )? (?<nick> \S+) /x
          nick = $~[:nick]
          self.channel.add_user(nick)
          self.channel[nick].set_mode(
            [:op, :voice].each_with_object({}) { |s,h|
              h[s] = !!$~[s] 
            }
          )
        end
      end
    end
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

  attr_accessor :network, :raw, :from, :command, :arguments, :text, :hide, :user, :log_format
  def initialize(network, string)
    @log_format = "%(network) %(raw)"
    @network = network
    @raw = string
    @hide = false
    
    match = MESSAGE.match( string ) or raise InvalidMEssage.new(string)

    @from = match[:prefix].to_sym if match[:prefix]
    @command = match[:command].to_sym
    @arguments = match[:arguments].split /\s+/
    @arguments.extend Array::Printable
    @text = match[:message]

    @user = CCCB::User.new( self )

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

  def nick
    @user.nick
  end

  def format(format_string)
    format_string.keyreplace { |key|
      self.send(key).to_s || ""
    }
  end
  
  def log
    info self.format(@log_format)
  end
end

class CCCB::User
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
    else
      @id = :system
      @nick = :system
      @user = :""
      @flag = :""
      @host = :""
    end
    @channels = []
    @timestamp = Time.now
  end

  def servermessage?
    !!@server
  end

end

class CCCB::ChannelUser

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

class CCCB::Channel

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
      @users[id] = CCCB::ChannelUser.new(user,self)
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
