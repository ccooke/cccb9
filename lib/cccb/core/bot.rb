module CCCB::Core::Bot
  extend Module::Requirements
  needs :hooks, :reload, :call_module_methods, :managed_threading
  
  LOG_CONVERSATION    = "%(network) [%(replyto)]"
  LOG_GENERIC         = "%(network) %(raw)"
  LOG_MODE_CHANNEL = "#{LOG_CONVERSATION} MODE %(args)"
  LOG_MODE_USER = "%(network) -!- MODE %(arguments) %(text)"

  LOG_FORMATS = {
    PRIVMSG:  "#{LOG_CONVERSATION} %(user) %(text)",
    NOTICE:   "%(network) -%(replyto)- %(user) -!- %(text)",
    PART:     "#{LOG_CONVERSATION} <<< %(nick) [%(from)] has left %(channel)",
    QUIT:     "#{LOG_CONVERSATION} <<< %(nick) [%(from)] has quit IRC",
    JOIN:     "#{LOG_CONVERSATION} <<< %(nick) [%(from)] has left %(channel)"
  }

  def add_irc_command(command, &block)
    spam "Declared irc command #{command}"
    bot.commands[command] = block
  end

  def hide_irc_commands(*commands)
    bot.hide_command_proc ||= Proc.new do |message|
      message.hide = true
    end
    commands.each do |command|
      spam "Hiding irc command #{command}"
      bot.commands[command] = bot.hide_command_proc
    end
  end

  def module_load
    bot.commands = {}

    add_hook :connected do |network|
      network.channels.each do |channel|
        network.puts "JOIN #{Array(channel).join(" ")}"
      end
    end

    add_hook :server_message do |message|
      message.log_format = LOG_FORMATS[message.command] || LOG_GENERIC
      if bot.commands.include? message.command
        bot.commands[message.command].( message )
      end
      schedule_hook message.command, message
      message.log unless message.hide?
    end

    add_irc_command :PING do |message|
      message.hide = true unless $DEBUG
      message.network.puts "PONG :#{message.text}" 
    end

    add_irc_command :PRIVMSG do |message|
      if message.ctcp?
        message.log_format = LOG_CTCP
        schedule_hook :ctcp, message
      else
        schedule_hook :privmsg, message
      end
    end

    add_irc_command :MODE do |message|
      message.hide = true
      if message.to_channel?
        message.log_format = LOG_MODE_CHANNEL
      else
        message.log_format = LOG_MODE_USER
      end
    end

    add_irc_command :"433" do |message|
    end

    add_irc_command :"353" do |message|
      message.hide = true
    end

    add_hook :JOIN do |message|
      if message.user.nick == 'ccooke'
        message.network.puts "MODE #{message.channel} +o #{message.user.nick}"
      end
    end

  end

  def putsuser( message, string )
    info "#{message.network} [#{message.replyto}] #{message.user} #{string}"
  end
end
