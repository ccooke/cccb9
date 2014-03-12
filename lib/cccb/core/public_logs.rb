require 'uri'

module CCCB::Core::PublicLogs
  extend Module::Requirements
  
  needs :bot

  def module_load
    add_setting :channel, "log_sessions", auth: :superuser
    set_setting "http://#{ %x{ hostname }.chomp  }/~ccooke/bot/logs/%(channel).log", "options", "log_url_format"
    set_setting false, "options", "logging"
    set_setting "cccb9.log", "options", "log_name"

    add_hook :public_log, :setting_set do |object, setting, key, old, new|
      next unless setting == "options" and object.is_a? CCCB::Channel
      next unless key == 'logging'
      next if  old == new
      word = new ? "enabled" : "disabled"
      url = object.format( object.get_setting("options", "log_url_format") )
      object.network.msg object.name, "Public logging #{word}. Logs are viewable at #{url}"
    end

    add_hook :public_log, :log_message do |string, target|
      next unless target.is_a? CCCB::Channel
      next unless target.get_setting( "options", "logging" )
      message = string.gsub /^\w+ \[[^\]]*\] /, ""
      file = "logs/#{target}.log"
      open( file, 'a' ) do |f|
        format = "[#{Time.now}] #{message}"
        f.puts format
      end
    end

    add_request( :public_log, /\s*(?<toggle>start|stop) session\s+(?<session>.*?)\s*$/i ) do |match, message|
      next unless message.to_channel?

      toggle = match[:toggle].downcase
      session = match[:session]

      if toggle == 'start'
        unless message.channel.get_setting("options", "logging")
          if message.channel.auth_setting(message, "logging")
            message.channel.set_setting(true, "options", "logging")
            url = message.channel.get_setting("options", "log_url_format")
            message.channel.set_setting(:auto, "log_sessions", session)
          else
            next "You are not authorised to enable logging"
          end
        end
      end

      file = "logs/#{ message.replyto.id }.log"
      string = "[%(time)] #{toggle.upcase} %(from) #{session}"
      open( file, 'a' ) { |f| f.puts message.format(string) }

      url = message.format( message.channel.get_setting("options", "log_url_format"), uri_escape: true )
      tag = URI.escape( session, "&?/=#" )
      url += "&tag=#{tag}"
      message.reply "Ok, logged session #{toggle} for #{session}. You can see this session at #{url}"

      next unless toggle == 'stop'
      next unless message.channel.get_setting("options", "logging")
      next unless message.channel.get_setting("log_sessions", session) == :auto
      message.channel.set_setting(nil, "log_sessions", session)
      next unless message.channel.get_setting("log_sessions").empty?

      if message.channel.auth_setting(message, "logging")
        message.channel.set_setting(false, "options", "logging")
        url = message.channel.get_setting("options", "log_url_format")
      else
        next "You are not authorised to disable logging"
      end

      nil

    end
  end
end
