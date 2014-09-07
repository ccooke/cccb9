
module CCCB::Core::CoreCommands
  extend Module::Requirements
  needs :commands
  
  def module_load

    add_command :debug, "show load errors" do |message, args|
      auth_command :superuser, message
      message.reply "Last (re)load at #{$load_time}"
      message.reply $load_errors
    end
    
    add_command :core, [ ["copy","cp"] ] do |message, args|
      raise "Two arguments are required" unless args.count == 2
      message.reply copy_user_setting( message, args[0], args[1] )
    end

    add_command :core, [ ["set","setting"], ["my","channel",""] ] do |message, args, words|
      settings = message.replyto.storage[:settings].keys
      if args.empty?
        message.reply "Found #{settings.count} settings here: #{settings.join(", ")}"
      else
        setting = args.shift
        args.shift if args[0] == '='
        value = args.join(' ') unless args.empty?
        default_type = if message.to_channel? and words.last == "channel"
          "channel"
        elsif words.last == "my"
          "user"
        end
        setting = parse_setting( setting, message, default_type )
        message.reply user_setting( message, setting, value )
      end
    end

    add_command :core, "admin reload" do |message|
      auth_command :superuser, message
      reload_then(message) do |m|
        if $load_errors.count == 0
          m.reply "Ok"
        else
          m.reply "There were #{$load_errors.count} error(s):"
          $load_errors.each { |e| m.reply e }
        end
      end
    end

    add_command :core, "admin superuser enable" do |message, args|
      password_valid = (args.join(" ") == CCCB.instance.superuser_password)
      message.reply( if message.to_channel?
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
      end)
    end

    add_command :core, "admin superuser disable" do |message|
      message.reply( if message.user.superuser?
        get_setting("superusers").delete message.from.downcase.to_s
        "Removed you from the superuser list."
      else
        "You weren't a superuser in the first place."
      end)
    end

    add_command :core, [ "admin superuser", [ "status", "" ] ] do |message|
      message.reply( if message.user.superuser?
        "You are a superuser"
      else
        "You are not a superuser"
      end )
    end

    add_command :core, "admin reconnect" do |message,args|
      auth_command :superuser, message
      network = if args[0]
        CCCB.instance.networking.networks[args[0]]
      else
        message.network
      end
      network.puts "QUIT Reconnecting"
    end
  end
end
