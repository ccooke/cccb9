# encoding: utf-8
require 'json'

module CCCB::Core::Bot
  class SettingError < Exception; end
  class LogException < Exception; end
  class PublicException < Exception; end
  class PrivateException < Exception; end

  extend Module::Requirements
  needs :hooks, :reload, :call_module_methods, :managed_threading, :events, :persist, :settings, :networking
  
  SETTING             = /
    (?<type> core | network | channel | user | [nuc]\([^\)]+\) ){0}
    (?<name> [-\w+]+ ){0}
    (?<key>  \S+     ){0}

    (?: 
      \g<type> :: \g<name> (?: :: \g<key>)? 
    |
      \g<name> :: \g<key>?
    |
      \g<key>
    )
  /x

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

  def parse_setting(setting,message,default_type = nil)
    if setting.respond_to? :to_hash
      if setting.include? :name or setting.include? :key
        return setting
      end
    end
    match = SETTING.match(setting) or raise "Invalid setting: #{setting}"
    data = %i{ type name key }.each_with_object({}) { |k,o| o[k] = match[k] }
    data[:type] ||= default_type || (message.to_channel? ? "channel" : "user")
    data[:name] ||= "options"
    data
  end

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

  def rate_limit_by_feature( message, feature, hook )
    if message.to_channel? 

      rate_key = feature.to_s
      rate_limit = nil

      if hook.to_s.start_with? 'command/'
        keys = hook.to_s.split('/')
        keys.shift
        search = keys.length.times.with_object([]) { |i,o|
          last = keys.pop
          o << [ "!command", *keys, last ].join('/') 
          o << [ "!command", *keys, '*' ].join('/') 
        }
        search << feature.to_s
        search.find do |k|
          rate_key = k
          rate_limit = message.channel.get_setting("rate_limit", k)
          not rate_limit.nil?
        end
      end 

      unless rate_limit.nil?
        timestamp = Time.now.to_f
        current = message.channel.get_setting("rate_limit_current")
        current[rate_key] ||= {
          bucket: rate_limit[:bucketsize],
          last_fill: timestamp,
          lock: Mutex.new
        }
        current = current[rate_key]
        current[:triggered_by] ||= nil
        current[:triggered_time] ||= 0
        current[:triggered_spam] ||= false
        current[:last_fill] = current[:last_fill].to_f
        current[:lock].synchronize do
          current[:bucket] += rate_limit[:fillrate] * ( timestamp - current[:last_fill] )
          current[:bucket] = rate_limit[:bucketsize] if current[:bucket] > rate_limit[:bucketsize]
          current[:last_fill] = timestamp
          if current[:bucket] < 1 
            seconds_between = 1.0 / rate_limit[:fillrate] 
            time_to_next = (1.0 - current[:bucket]) / rate_limit[:fillrate] 

            message_extra = message.channel.get_setting("options", "rate_limit_message")
            if timestamp - current[:triggered_time] > seconds_between
              current[:triggered_by] = message.user
              current[:triggered_time] = timestamp
              current[:triggered_spam] = nil
              raise PrivateException.new( "#{rate_key} is rate limited in #{message.channel}. Next use in #{sprintf "%.2f", time_to_next}s. #{message_extra}" )
            elsif timestamp - current[:triggered_time] <= seconds_between and not current[:triggered_spam]
              current[:triggered_spam] = true
              raise PublicException.new( "#{message.user.nick}: #{rate_key} is rate limited in #{message.channel}. Next use in #{sprintf "%.2f", time_to_next}s. #{message_extra}" )
            else
              raise LogException.new( "#{message.user.nick}: #{rate_key} is rate limited in #{message.channel}. Next use in #{sprintf "%.2f", time_to_next}s. #{message_extra}" )
            end
          end
        end
        current[:bucket] -= 1
      end
    end
  end

  TIME_VALUES = {
    seconds: 1,
    minutes: 60,
    hours: 3600,
    days: 86400,
    weeks: 7 * 86400,
    years: 52 * 7 * 86400
  }
  def elapsed_time(seconds)
    seconds = seconds.to_i
    TIME_VALUES.sort_by { |(k,v)| v }.reverse.inject("") do |s,(k,v)|
      if seconds / v > 0
        n = seconds / v
        seconds = seconds % v
        s += "#{n} #{k} "
      else
        s
      end
    end
  end

  def add_request feature, regex, &block
    add_hook feature, :request, generator: 1 do |request, message|
      if match = regex.match( request )
        debug "REQ: Matched #{regex}"
        begin 
          rate_limit_by_feature( message, feature, :request )
          result = block.call( match, message  )
          if message.to_channel? 
            result = Array(result).map { |l| "#{message.nick}: #{l}" }
          end
          message.reply Array(result) unless Array(result).empty?
        rescue LogException => e
          debug "Log Exception: #{e}"
        rescue PrivateException => e
          debug "Private Exception for #{message.user}: #{e}"
          message.network.msg message.nick, e.to_s
        rescue PublicException => e
          debug "Exception: #{e}"
          message.reply e.to_s
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
    when /^n(?:etwork)?\((?<network>[^\]]+)\)$/i
      CCCB.instance.networking.networks[$~[:network].downcase]
    else
      message.network.channels[use_type.downcase] || message.network.users[use_type.downcase]
    end
  end

  def user_setting_value message, type, name, key, value_string = nil
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
    real_object = object.setting_object(name)

    spam "Got translation: #{translation.inspect}"
    if object != real_object
      real_object = "#{object}(::#{real_object})"
    end
    if translation and key and translation.include? key
      setting_name = [ real_object, name, translation[key] ] .compact.join('::')
      key = translation[key]
    else
      setting_name = [ real_object, name, key ].compact.join('::')
    end

    value = if key
      { key => object.get_setting(name,key) }
    else
      tmp = object.get_setting(name)
      if tmp.nil?
        raise CCCB::Settings::NoSuchSettingError.new("No such setting: #{name}")
      else
        tmp.dup
      end
    end

    return setting_name, value, key, object
  end

  def copy_user_setting message, source, destination
    source = parse_setting(source,message)
    destination = parse_setting(destination,source)

    setting_name, value, key, object = user_setting_value( message, source[:type], source[:name], source[:key] )
    destination_key = if key and ! destination[:dest_key]
      key
    else
      destination[:key]
    end
    dest_setting_name, dest_value, dest_key, dest_object = user_setting_value( message, destination[:type], destination[:name], destination_key )

    value = if key
      value[key]
    else
      value
    end

    dest_object.set_setting( Marshal.load( Marshal.dump( value ) ), destination[:name], dest_key )
    "Ok"
  end

  def user_setting message, setting, value_string = nil
    begin 
      setting = parse_setting(setting,message)
      setting_name, copy, key, object = user_setting_value( message, setting[:type], setting[:name], setting[:key], value_string )

      value = if object.setting_option(setting[:name], :secret) and message.to_channel?
        "<secret>"
      else
        object.setting_option(setting[:name],:hide_keys).each do |k|
          if copy.delete(k) and key and k == key
            copy[k] = "<secret>"
          end
        end

        if key
          copy = copy[key]
        end
        begin
          copy.to_json
        rescue Encoding::UndefinedConversionError => e
          #pp copy
        end
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
    
    add_setting :core, "superusers", default: []
    add_setting :user, "options"
    add_setting :channel, "options" 
    add_setting :network, "options"
    add_setting :core, "options"
    add_setting :core, "settings"
    add_setting :core, "rate_limit"
    add_setting :network, "rate_limit"
    add_setting :channel, "rate_limit"
    add_setting :channel, "rate_limit_current", auth: :superuser, persist: false
    default_setting true, "options", "join_on_invite"
    default_setting true, "options", "bang_commands_enabled"
    default_setting "", "options", "rate_limit_message"

    add_hook :core, :pre_setting_set do |obj, setting, hash|
      next unless setting == 'rate_limit' and hash.respond_to? :to_hash
      hash.each do |key, value|
        next if value.nil?
        unless match = value.match(/^ \s* (?<bucket> \d+(?:\.\d+)? ) \s* \+ \s* (?<fillrate> \d+(?:\.\d+)?) \s*$/x)
          raise "Invalid setting for rate_limit::#{key} '#{value}' should be of the form '<bucketsize> + <fillrate>' (e.g.: 40+0.5)"
        else
          hash[key] = { 
            bucketsize: match[:bucket].to_f,
            fillrate: match[:fillrate].to_f
          }
        end
      end
    end

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

    hide_irc_commands :"315", :"352", :"366", :"QUIT", :"303"
    hide_irc_commands :PING unless $DEBUG

    add_hook :core, :server_send do |network, string|
      spam "[#{network}] >>> #{string}"
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
      request = if message.text =~ /
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
        if message.to_channel?
          next if $~[:bang] and not message.channel.get_setting("options", "bang_commands_enabled")
        end
        $~[:request]
      else
        next if message.to_channel?
        message.text
      end

      run_hooks :request, request, message
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
  end

  def module_start
    bot.command_lock.lock
  end
end
