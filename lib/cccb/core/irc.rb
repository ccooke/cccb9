module CCCB::Core::IRC
  extend Module::Requirements
  needs :hooks, :reload, :call_module_methods

  def add_irc_command(command, &block)
    debug "Declared irc command #{command}"
    @irc_commands[command] = block
  end

  def hide_irc_commands(*commands)
    @hide_irc_command_proc ||= Proc.new do |message|
      message.hide = true
    end
    commands.each do |command|
      debug "Hiding irc command #{command}"
      @irc_commands[command] = @hide_irc_command_proc
    end
  end

  def module_load
    @irc_commands = {}

    add_hook :connected do |network|
      network.channels.each do |channel|
        network.puts "JOIN #{Array(channel).join(" ")}"
      end
    end

    add_hook :message do |message|
      if @irc_commands.include? message.command
        @irc_commands[message.command].( message )
      end
      schedule_hook message.command, message
      info "#{message.network} #{message}" unless message.hide?
    end

    add_irc_command :PING do |message|
      message.hide = true unless $DEBUG
      message.network.puts "PONG :#{message.text}" 
    end

    add_irc_command :NOTICE do |message|
      message.hide = true
      info "#{message.network} #{message.from} -!- #{message.text}"
    end

    add_irc_command :PART do |message|
      message.hide = true
      message.channel.remove_user(message.user)
      info "#{message.network} [#{message.channel}] <<< #{message.user.nick} [#{message.from}] has left #{message.channel}"
    end

    add_irc_command :JOIN do |message|
      message.hide = true
      message.channel.add_user(message.user)
      info "#{message.network} [#{message.channel}] >>> #{message.user.nick} [#{message.from}] has joined #{message.channel}"
    end

    add_irc_command :PRIVMSG do |message|
      message.hide = true
      if message.ctcp?
        schedule_hook :ctcp, message
      else
        schedule_hook :privmsg, message
      end
    end

    add_irc_command :MODE do |message|
      message.hide = true
      if message.to_channel?
        pattern = message.arguments[1].each_char
        mode = '+'
        message.arguments[2,message.arguments.length].each do |nick|
          case ch = pattern.next
          when '+', '-'
            mode = ch
            redo
          when 'o'
            message.channel[nick].set_mode op: !!(mode=='+')
          when 'v'
            message.channel[nick].set_mode voice: !!(mode=='+')
          end
        end
        args = message.arguments.dup
        args.shift
        info "#{message.network} [#{message.channel}] MODE #{args.join(" ")}"
      else
        info "#{message.network} -!- MODE #{message.arguments.join(" ")} #{message.text}"
      end
    end

    add_irc_command :"353" do |message|
      message.hide = true
      channel = message.network.channel( message.arguments[2] )
      message.text.split(/\s+/).each do |user|
        if user =~ /^ (?: (?<op> [@] ) | (?<voice> [+] ) )? (?<nick> \S+) /x
          nick = $~[:nick]
          channel.add_user(nick)
          channel[nick].set_mode(
            [:op, :voice].each_with_object({}) { |s,h|
              h[s] = !!$~[s] 
            }
          )
        end
      end
    end

    add_hook :privmsg do |message|
      info "#{message.network} [#{message.replyto}] #{message.user} #{message.text}"
    end

    add_hook :JOIN do |message|
      if message.user.nick == 'ccooke'
        message.network.puts "MODE #{message.channel} +o #{message.user.nick}"
      end
    end

    hide_irc_commands :"366"
  end
end
