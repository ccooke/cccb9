require 'json'

module CCCB::Core::Bot
  extend Module::Requirements
  needs :hooks, :reload, :call_module_methods, :managed_threading, :events, :persist
  
  LOG_CONVERSATION    = "%(network) [%(replyto)]"
  LOG_GENERIC         = "%(network) %(raw)"
  LOG_SERVER          = "%(network) ***%(command)*** %(text)"
  LOG_MODE_CHANNEL    = "#{LOG_CONVERSATION} MODE %(args)"
  LOG_MODE_USER       = "%(network) -!- MODE %(arguments) %(text)"
  LOG_CTCP            = "%(network) %(replyto) sent a CTCP %(ctcp) (%(ctcp_params))"

  LOG_FORMATS = {
    PRIVMSG:  "#{LOG_CONVERSATION} %(user) %(text)",
    NOTICE:   "%(network) -%(user)- -!- %(text)",
    PART:     "#{LOG_CONVERSATION} <<< %(nick) [%(from)] has left %(channel)",
    JOIN:     "#{LOG_CONVERSATION} >>> %(nick) [%(from)] has joined %(channel)"
  }

  def add_irc_command(command, &block)
    raise Exception.new("Use hooks instead") if bot.command_lock.locked?
    spam "Declared irc command #{command}"
    bot.commands[command] = block
  end
  private :add_irc_command

  def hide_irc_commands(*commands)
    raise Exception.new("Use hooks instead") if bot.command_lock.locked?
    commands.each do |command|
      spam "Hiding irc command #{command}"
      bot.commands[command] = Proc.new do |message|
        message.hide = true
      end
    end
  end
  private :hide_irc_commands

  def show_known_users(channel)
    longest = channel.users.values.map(&:to_s).max_by(&:length)
    columns = 60 / (longest.length + 2)
    channel.users.values.each_slice(columns) do |slice|
      info "#{channel.network} [#{channel}] [ #{
        slice.map { |s| sprintf "%-#{longest.length}s", s }.join("  ")
      } ] "
    end
  end

  def add_request regex, &block
    add_hook :request do |request, message|
      if match = regex.match( request )
        debug "REQ: Matched #{regex}"
        result = block.call( match, message  )
        if message.to_channel? 
          result = Array(result).map { |l| "#{message.nick}: #{l}" }
        end
        message.network.msg message.replyto, Array(result) unless result.nil?
      end
    end
  end

  def add_ctcp command, &block
    add_hook :ctcp do |message|
      spam "IN CTCP #{ command }"
      if message.ctcp == command
        debug "Accepted CTCP command #{command}"
        reply = block.call( message )
        unless reply.nil?
          message.network.notice message.replyto, "\001#{command} #{reply}\001"
        end
      end
    end
  end

  def module_load

    bot.command_lock ||= Mutex.new.lock
    bot.command_lock.unlock
    persist.store.define CCCB, :class
    persist.store.define CCCB::Network, :name
    persist.store.define CCCB::User, :id
    persist.store.define CCCB::Channel, :name

    bot.commands = {}

    add_hook :connected do |network|
      network.auto_join_channels.each do |channel|
        network.puts "JOIN #{Array(channel).join(" ")}"
      end
    end

    hide_irc_commands :"315", :"352", :"366", :"QUIT"
    hide_irc_commands :PING unless $DEBUG

    add_hook :server_message do |message|
      message.log_format = LOG_FORMATS[message.command] || LOG_SERVER
      if bot.commands.include? message.command
        bot.commands[message.command].( message )
      end
      schedule_hook message.command_downcase, message
      message.log unless message.hide?
    end

    add_hook :client_privmsg do |network, target, string|
      info "#{network} [#{target}] < #{network.nick}> #{string}"
    end

    add_hook :client_notice do |network, target, string|
      info "#{network} [#{target}] -#{network.nick}- NOTICE #{string}"
    end

    add_irc_command :PRIVMSG do |message|
      if message.ctcp?
        message.log_format = LOG_CTCP
        schedule_hook :ctcp, message
      else
        message.user.persist[:history] = message.user.history
        schedule_hook :message, message
      end
    end

    add_irc_command :MODE do |message|
      message.hide = true
      if message.to_channel?
        message.log_format = LOG_MODE_CHANNEL
        schedule_hook :mode_channel, message
      else
        message.log_format = LOG_MODE_USER
        schedule_hook :mode_user, message
      end
    end

    add_irc_command :NICK do |message|
      message.hide = true
      message.user.channels.each do |channel|
        info message.format("%(network) [#{channel}] %(old_nick) is now known as %(nick)")
        schedule_hook :rename, channel, message.user, message.old_nick
      end
    end

    add_irc_command :"315" do |message|
      message.hide = true
      show_known_users message.channel
      info message.format("#{LOG_CONVERSATION} --- Ready on %(channel)")
      schedule_hook :joined, message.channel
    end

    add_hook :quit do |message|
      message.channels_removed.each do |channel|
        info message.format("%(network) [#{channel}] <<< %(nick) [%(from)] has left IRC (%(text))")
      end
      info "Persist-after #{persist.store.dump}"
    end

    add_hook :join do |message|
      if message.user.nick == 'ccooke'
        message.network.puts "MODE #{message.channel} +o #{message.user.nick}"
      end
    end

    add_hook :message do |message|
      if message.to_channel?
        if message.text =~ /^\s*#{message.network.nick}:\s*(?<request>.*?)\s*$/
          schedule_hook :request, $~[:request], message
        end
      else
        schedule_hook :request, message.text, message
      end
    end
    
    add_request /^test (.*)$/ do |match, message|
      "Test ok: #{match[1]}"
    end

    add_request /^
      \s* setting \s*
      (?:
        (?<type>core|channel|network|user|channeluser|[^:]+?)
        ::
      |
        ::
      )?
      (?<setting> \w+)
      (?:
        ::
        (?<key> \w+)
      )?
      (?:
        \s+
        =
        \s*
        (?<value>.*?)
      )?
      \s*$
    /x do |match, message|
      name = match[:setting]
      type = if match[:type]
        match[:type]
      elsif message.to_channel?
        :channel
      else
        :user
      end
      type_name = 'core'
        
      object = case type.to_sym
      when :core 
        CCCB.instance
      when :channel 
        message.channel 
      when :network 
        message.network
      when :user 
        message.user
      when :channeluser 
        message.channeluser
      else
        message.network.channels[type.downcase] || message.network.users[type.downcase]
      end

      key = match[:key]

      setting_name = [ object, name, key ].compact.join('::')

      if object.nil?
        "Unable to find #{setting_name} in #{match[:type]}::#{match[:setting]}"
      elsif object.auth_setting( message, name )
        if match[:value]
          begin
            value = case match[:value]
            when "nil", ""
              nil
            when "true"
              true
            when "false"
              false
            else
              JSON.parse( "[ #{match[:value].inspect} ]", create_additions: false ).first
            end

            object.set_setting(name, value, key)
            "Setting #{setting_name} is now set to #{object.get_setting(name,key)}"
          rescue Exception => e
            info "EXCEPTION: #{e} #{e.backtrace}"
            "Sorry, I couldn't parse #{match[:value]} (#{e})"
          end
        else
          "Setting #{setting_name} is currently set to #{object.get_setting(name,key).to_json}"
        end
      else
        "Denied"
      end
    end

    add_request /^\s*reload\s*$/i do |match, message|
      if message.user.superuser?
        reload_then(message) do |message|
          if reload.errors.count == 0
            message.network.msg message.replyto, "Ok"
          else
            message.network.msg message.replyto, reload.errors
          end
        end
        nil
      else
        "Denied"
      end
    end

    add_ctcp :PING do |message|
      message.ctcp_params.join(" ")
    end

    add_ctcp :VERSION do |message|
      "CCCB v#{CCCB::VERSION}"
    end
  end

  def module_start
    bot.command_lock.lock
  end
end
