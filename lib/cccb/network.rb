require 'thread'

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

  attr_reader :queue

  def configure(conf)
    @queue = Queue.new
    @client = CCCB.instance
    @actors = {}
    @pending = ""
    @channels = {}
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
      @channels[name] = CCCB::Channel.new( message.replyto, message.user )
    else
      @channels[name].add_user( message.user )
    end
    @channels[name]
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
    STDOUT.puts "Exception #{e}"
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

  def user(from)
  end

end


