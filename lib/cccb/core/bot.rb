require 'json'

module CCCB::Core::Bot
  class SettingError < Exception; end

  extend Module::Requirements
  needs :hooks, :reload, :call_module_methods, :managed_threading, :events, :persist, :settings, :networking
  
  LOG_CONVERSATION    = "%(network) [%(replyto)]"
  LOG_GENERIC         = "%(network) %(raw)"
  LOG_SERVER          = "%(network) ***%(command)*** %(text)"
  LOG_CTCP            = "%(network) %(replyto) sent a CTCP %(ctcp) (%(ctcp_params))"

  LOG_FORMATS = {
    PRIVMSG:      "#{LOG_CONVERSATION} <%(nick_with_mode)> %(text)",
    ctcp_ACTION:  "#{LOG_CONVERSATION} * %(nick_with_mode) %(ctcp_text)",
    NOTICE:       "%(network) -%(user)- -!- %(text)",
    PART:         "#{LOG_CONVERSATION} <<< %(nick) [%(from)] has left %(channel)",
    JOIN:         "#{LOG_CONVERSATION} >>> %(nick) [%(from)] has joined %(channel)",
    MODE:         "#{LOG_CONVERSATION} MODE [%(arg1toN)] by %(nick_with_mode)"
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

  def add_request feature, regex, &block
    add_hook feature, :request, generator: true do |request, message|
      if match = regex.match( request )
        debug "REQ: Matched #{regex}"
        begin 
          result = block.call( match, message  )
          if message.to_channel? 
            result = Array(result).map { |l| "#{message.nick}: #{l}" }
          end
          message.reply Array(result) unless result.nil?
        rescue Exception => e
          message.reply "Sorry, that didnt work: #{e}"
          verbose "#{e} #{e.backtrace}"
        end
      end
    end
  end

  def resolve_object_type message, type
    use_type = if type
      type
    elsif message.to_channel?
      :channel
    else
      :user
    end

    case use_type.to_sym
    when :core 
      CCCB.instance
    when :channel 
      message.channel 
    when :network 
      message.network
    when :user, :my
      message.user
    when :channeluser 
      message.channeluser
    when /^u(?:ser)?\((?<user>[^\]]+)\)$/i
      message.network.get_user($~[:user].downcase)
    when /^c(?:hannel)?\((?<channel>#[^\]]+)\)$/i
      message.network.get_channel($~[:channel].downcase)
    when /^n(?:etwork)?\((?<network>#[^\]]+)\)$/i
      CCCB.instance.networking.networks[$~[:network].downcase]
    else
      message.network.channels[use_type.downcase] || message.network.users[use_type.downcase]
    end
  end

  def user_setting_value message, type, name, key, value_string = nil
    verbose [ type, name, key ].inspect
    object = resolve_object_type( message, type )
    setting_name = [ object, name, key ].compact.join('::')
    
    raise SettingError.new("Unable to find #{setting_name} in #{object}::#{name}") if object.nil?
    raise SettingError.new("Denied: #{object.auth_reject_reason}") unless object.auth_setting( message, name)

    translation = if value_string
      begin
        value = case value_string
        when "nil", ""
          nil
        when "true"
          true
        when "false"
          false
        when /^\s*[\[\{]/
          JSON.parse( "[ #{value_string} ]", create_additions: false ).first
        else
          value_string
        end

        object.set_setting(value, name, key)
      rescue Exception => e
        verbose "EXCEPTION: #{e} #{e.backtrace}"
        raise SettingError.new("Sorry, there's something wrong with the value '#{value_string}' (#{e})")
      end
    end

    verbose "Got translation: #{translation.inspect}"
    if translation and key and translation.include? key
      setting_name = [ object, name, translation[key] ] .compact.join('::')
      key = translation[key]
    end

    value = if key
      { key => object.get_setting(name,key) }
    else
      object.get_setting(name).dup
    end

    return setting_name, value, key, object
  end

  def copy_user_setting message, type, name, key, dest_type, dest_name, dest_key
    setting_name, value, key, object = user_setting_value( message, type, name, key )
    if key and ! dest_key
      dest_key = key
    end
    dest_setting_name, dest_value, dest_key, dest_object = user_setting_value( message, dest_type, dest_name, dest_key )

    value = if key
      value[key]
    else
      value
    end

    dest_object.set_setting( Marshal.load( Marshal.dump( value ) ), dest_name, dest_key )
    "Ok"
  end

  def user_setting message, type, name, key, value_string = nil
    begin 
      setting_name, copy, key, object = user_setting_value( message, type, name, key, value_string )

      value = if object.setting_option(name, :secret) and message.to_channel?
        "<secret>"
      else
        object.setting_option(name,:hide_keys).each do |k|
          if copy.delete(k) and key and k == key
            copy[k] = "<secret>"
          end
        end

        if key
          copy = copy[key]
        end
        copy.to_json
      end

      return "Setting #{setting_name} is set to #{value}"
    rescue SettingError => e
      return e.message
    end
  end

  def write_to_log string, target = nil
    info string
    schedule_hook :log_message, string, target if target
  end

  def module_load

    bot.command_lock ||= Mutex.new.lock
    bot.command_lock.unlock
    persist.store.define CCCB, :class
    persist.store.define CCCB::Network, :name
    persist.store.define CCCB::User, :network, :id
    persist.store.define CCCB::Channel, :network, :name 

    add_setting :core, "superusers", default: []
    add_setting :user, "options"
    add_setting :channel, "options" 
    add_setting :network, "options"
    add_setting :core, "options"
    set_setting true, "options", "join_on_invite"
    set_setting true, "options", "bang_commands_enabled"

    ( networking.networks.count * 2 + 1 ).times do
      add_hook_runner
    end

    add_setting_method :user, :superuser? do
      CCCB.instance.get_setting("superusers").include? self.from.to_s.downcase
    end
    bot.commands = {}

    add_hook :core, :connected do |network|
      info "CONNECTED #{network}"
      network.auto_join_channels.each do |channel|
        network.puts "JOIN #{Array(channel).join(" ")}"
      end
    end

    hide_irc_commands :"315", :"352", :"366", :"QUIT"
    hide_irc_commands :PING unless $DEBUG

    add_hook :core, :server_send do |network, string|
      spam ">>> " + string, network
    end

    add_hook :core, :server_message do |message|
      message.log_format = LOG_FORMATS[message.command] || LOG_SERVER
      if bot.commands.include? message.command
        bot.commands[message.command].( message )
      end
      schedule_hook message.command_downcase, message
      write_to_log message.format( message.log_format) unless message.hide?
    end

    add_hook :core, :client_privmsg do |network, target, string|
      nick = if target.respond_to? :user_by_name
        target.user_by_name(network.nick).nick_with_mode
      else
        network.nick
      end
      write_to_log "#{network} [#{target}] <#{nick}> #{string}", target
    end

    add_hook :core, :client_notice do |network, target, string|
      nick = if target.respond_to? :user_by_name
        target.user_by_name(network.nick).nick_with_mode
      else
        network.nick
      end
      write_to_log "#{network} [#{target}] -#{nick}- NOTICE #{string}", target
    end

    add_irc_command :PRIVMSG do |message|
      if message.ctcp?
        sym = :"ctcp_#{message.ctcp}"
        message.log_format = LOG_FORMATS[sym] || LOG_CTCP
        write_to_log message.format(message.log_format), message.replyto
        message.hide = true
        run_hooks sym, message
      else
        write_to_log message.format(message.log_format), message.replyto
        message.hide = true
        message.user.persist[:history] = message.user.history
        run_hooks :message, message
      end
    end

    add_irc_command :MODE do |message|
      if message.to_channel?
        run_hooks :mode_channel, message
      else
        run_hooks :mode_user, message
      end
    end

    add_irc_command :NICK do |message|
      message.hide = true
      message.user.channels.each do |channel|
        write_to_log message.format("%(network) [#{channel}] %(old_nick) is now known as %(nick)"), channel
        run_hooks :rename, channel, message.user, message.old_nick
      end
    end

    add_irc_command :INVITE do |message|
      if message.network.get_setting("options", "join_on_invite")
        warning "Invited to channel #{message.text} by #{message.user}"
        message.network.puts "JOIN #{message.text}"
      end
    end

    add_irc_command :"315" do |message|
      message.hide = true
      show_known_users message.channel
      write_to_log message.format("#{LOG_CONVERSATION} --- Ready on %(channel)"), message.channel
      run_hooks :joined, message.channel
    end

    add_hook :core, :quit do |message|
      message.channels_removed.each do |channel|
        write_to_log message.format("%(network) [#{channel}] <<< %(nick) [%(from)] has left IRC (%(text))"), channel
      end
    end

    add_hook :core, :message do |message|
      if message.to_channel?
        if message.text =~ /
          ^
          \s*
          (?:
            #{message.network.nick}: \s* (?<request>.*?) 
          |
            (?<bang> ! ) \s* (?<request> .*? )
          )
          \s*
          $
        /x
          next if $~[:bang] and not message.channel.get_setting("options", "bang_commands_enabled")
          run_hooks :request, $~[:request], message
        end
      else
        run_hooks :request, message.text, message
      end
    end
    
    add_request :debug, /^test (.*)$/ do |match, message|
      "Test ok: #{match[1]}"
    end

    add_request :debug, /^show load errors$/ do |match, message|
      message.reply "Last (re)load at #{$load_time}"
      message.reply $load_errors
      nil
    end

    add_request :core, /^
      \s*
      copy
      \s+ 
      (?<type> [^:]+ )
      ::
      (?<setting> [-\w+]+)
      (?:
        ::
        (?<key> [^\s=]+ )
      )?
      \s+
      (?<dest_type> [^:]+ )
      ::
      (?<dest_setting> [-\w+]+)
      (?:
        ::
        (?<dest_key> [^\s=]+ )
      )?
      $
    /xi do |match, message|
      copy_user_setting( message, match[:type], match[:setting], match[:key], match[:dest_type], match[:dest_setting], match[:dest_key] )
    end

    add_request :core, /^
      \s* setting \s+
      (?:
        (?<type>core|channel|network|user|channeluser|[^:]+?)
        ::
      |
        ::
      )?
      (?<setting> [-\w]+)
      (?:
        ::
        (?<key> [^\s=]+)
      )?
      (?:
        \s+
        =
        \s*
        (?<value>.*?)
      )?
      \s*$
    /xi do |match, message|
      name = match[:setting]
        
      key = match[:key]
      user_setting( message, match[:type], name, key, match[:value] )
    end

    add_request :core, /^
      \s* set \s+
      (?:
        (?<object> my | channel )
      | 
        (?<object> \#\S+ ) 's
      )
      (?:
        \s+
        (?<key> \S+)
        (?: 
          \s+
          to
          \s+
          (?<value> .*? )
        )?
      )?
      \s*$
    /xi do |match, message|
      user_setting( message, match[:object], "options", match[:key], match[:value] )
    end

    add_request :core, /^\s*reload\s*$/i do |match, message|
      if message.user.superuser?
        reload_then(message) do |message|
          if reload.errors.count == 0
            message.reply "Ok"
          else
            message.reply reload.errors
          end
        end
        nil
      else
        "Denied"
      end
    end

    add_hook :core, :ctcp_ACTION do |message|
      message.hide = true
      run_hooks :message, message
    end

    add_hook :core, :ctcp_PING do |message|
      message.reply message.ctcp_params.join(" ")
    end

    add_hook :core, :ctcp_VERSION do |message|
      message.reply "CCCB v#{CCCB::VERSION}"
    end

    add_request :core, /^\s*superuser\s+override\s*(?<password>.*?)\s*$/ do |match, message|
      password_valid = (match[:password] == CCCB.instance.superuser_password)
      if message.to_channel?
        if password_valid
          CCCB.instance.superuser_password = (1..32).map { (rand(64) + 32).chr }.join
        end
        "Denied. And don't try to use that password again."
      else
        if password_valid
          get_setting("superusers") << message.from.downcase.to_s
          "Okay, you are now a superuser"
        else
          "Denied"
        end
      end
    end

    add_request :core, /^\s*superuser\s+resign\s*$/ do |match, message|
      if message.user.superuser?
        get_setting("superusers").delete message.from.downcase.to_s
        "Removed you from the superuser list."
      else
        "You weren't a superuser in the first place."
      end
    end

    add_request :core, /^reconnect(?:\s+(?<network>\w+))?\s*$/ do |match, message|
      next "Denied" unless message.user.superuser?
      network = if match[:network]
        CCCB.instance.networking.networks[match[:network]]
      else
        message.network
      end
      network.puts "QUIT Reconnecting"
    end
  end

  def module_start
    bot.command_lock.lock
  end
end
