require 'tzinfo'
require 'tzinfo/data'

module CCCB::Core::UserTrack
  extend Module::Requirements

  needs :bot, :session

  def usertime(user, use_time = nil)
    use_time ||= Time.now
    if timezone_name = user.get_setting("options", "timezone")
      timezone = ::TZInfo::Timezone.get(timezone_name)
      offset = timezone.current_period.offset.utc_offset
      hours = offset / 3600
      minutes = ( offset % 3600 ) / 60
      usable_offset = format("%+03d:%02d", hours, minutes)
      use_time.localtime(usable_offset)
    else
      use_time
    end
  end

  def module_load

    add_setting :user, "user_tracking", auth: :superuser, secret: true

    add_hook :user_tracking, :pre_setting_set do |obj, setting, hash|
      next unless obj.is_a? CCCB::User
      next unless setting == "options" and hash.include? "timezone"
      begin
        ::TZInfo::Timezone.get(hash['timezone'])
      rescue 
        raise "Invalid timezone: #{hash['timezone']}. Pick the closest entry in http://en.wikipedia.org/wiki/List_of_tz_database_time_zones e.g.: Europe/London"
      end
    end

    add_hook :user_tracking, [:join, :nick, :privmsg] do |message|
      if tells = message.user.get_setting("user_tracking", "tells")
        tells.delete_if do |(user,time,tell)|
          message.network.msg message.user.name, "#{user} left a message at #{usertime(message.user,time)}: #{tell}"
          true
        end
      end
    end

    add_command :user_tracking, "seen" do |message, (username)|
      raise "Who?" if username.nil?
      user = message.network.get_user(username.downcase, autovivify: false)
      info user.inspect
      message.reply (if user.nil?
        "I have no record of that user. Sorry."
      elsif user == message.user
        "I don't know. Have you seen yourself?"
      elsif user.name == message.network.nick
        "Yes."
      else
        "I last saw #{user} active at #{usertime( message.user, user.history.last.time )}#{
          if message.to_channel? and user.channel_history.include? message.channel.name
            saved_message = user.channel_history[message.channel.name]
            text = if saved_message.ctcp?
              saved_message.format("* %(nick_with_mode) %(ctcp_text)")
            else
              saved_message.format("<%(nick_with_mode)> %(text)")
            end
            " saying '#{text}'"
          end
        }. #{
          if user.channels.count == 0
            "I can't see them online at the moment, though."
          elsif user.channels.any? { |c| message.user.channels.include? c }
            "I can see them currently online in at least one channel you're in."
          else
            "You can't see them online at the moment, though."
          end
        }"
      end )
    end

    add_command :user_tracking, "tell" do |message, args|
      raise "Who?" if args[0].nil?
      username = args.shift
      raise "Tell #{username} what?" if args[0].nil?
      note = args.join(' ')
      user = message.network.get_user(username.downcase)
      tells = user.get_setting("user_tracking", "tells")
      if tells.nil?
        tells = []
        user.set_setting( tells, "user_tracking", "tells")
      end      

      message.reply( if user.channels.count == 0
        tells << [ message.user, message.time, note ]
        "Ok"
      else
        "They appear to still be online. Try sending that to them directly."
      end )
    end

  end
end
