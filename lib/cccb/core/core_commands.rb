
module CCCB::Core::CoreCommands
  extend Module::Requirements
  needs :commands
  
  def module_load
    #@doc
    # This (superuser only) command is a pure IRC passthrough
    add_command :debug, "puppet" do |message, args|
      auth_command :superuser, message
      message.network.puts args.join(" ")
    end

    #@doc
    # This (superuser only) command displays load errors from the last reload"
    add_command :debug, "show load errors" do |message, args|
      auth_command :superuser, message
      message.reply.force_title = "Last (re)load at #{$load_time}"
      message.reply.summary = $load_errors.dup + [ "-- #{$load_errors.count} errors" ]
    end
    
    #@doc
    #@param source Setting A CCCB setting (of the form object::group[::name])
    #@param dest Setting A CCCB setting (e.g.: channel::options)
    # Copies a setting from one place to another
    # Examples:
    # copy channel::options c(#other_channel)::options
    # *Note*: This requires the user has access to *both* settings
    add_command :core, [ ["copy","cp"] ] do |message, args|
      raise "Two arguments are required" unless args.count == 2
      message.reply.summary = copy_user_setting( message, args[0], args[1] )
    end

    #@doc
    #@param setting Setting A CCCB setting (of the form object::group[::name])
    #@param value Data (Optional) data. Use 'nil' to clear the value of a setting
    # Stores a CCCB setting. 
    # Settings can be stored at several levels - on users, channels, networks and the core of the bot. 
    # Users by default have access to settings on their own user object, while chanops are required to set channel settings
    # Examples:
    # set core::allowed_features::dice = true
    #      - Enable the 'dice' feature, turning on the 'roll', 'prob' and other commands
    # set channel::options::auto_cut_length = 512
    #      - Tells the bot to infomr people their lines might have cut off if they are exactly 512 bytes long
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
        message.reply.summary = user_setting( message, setting, value )
      end
    end

    #@doc
    # This (superuser only) command reloads the bot
    add_command :core, "admin reload" do |message|
      auth_command :superuser, message
      message.clear_reply
      reload_then(message) do |m|
        begin
          if $load_errors.count == 0
            m.reply.title = "Reload successful"
          else
            m.reply.force_title = "Reload failed: #{$load_errors.count} error(s)"
            m.reply.summary = $load_errors.dup
          end
          # This needs to be here because this code executes after the reload
          r = m.send_reply
        rescue Exception => e
          error "Error in reload_then block: #{e}"
          error "#{e.backtrace}"
        end
      end
    end

    #@doc
    # (With a password) this command allows a user to become a superuser
    add_command :core, "admin superuser enable" do |message, args|
      password_valid = (args.join(" ") == CCCB.instance.superuser_password)
      message.reply.summary = if message.to_channel?
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

    #@doc
    # This command removes the current user from the superuser list
    add_command :core, "admin superuser disable" do |message|
      message.reply.summary = if message.user.superuser?
        get_setting("superusers").delete message.from.downcase.to_s
        "Removed you from the superuser list."
      else
        "You weren't a superuser in the first place."
      end
    end

    #@doc
    # Tells you if you are a superuser
    add_command :core, [ "admin superuser", [ "status", "" ] ] do |message|
      message.reply.summary = if message.user.superuser?
        "You are a superuser"
      else
        "You are not a superuser"
      end
    end

    #@doc
    #@param network String A Network name 'freenode', 'lspace', etc
    # Tells the bot to disconnect and reconnect to the given network
    add_command :core, "admin reconnect" do |message,args|
      auth_command :superuser, message
      network = if args[0]
        CCCB.instance.networking.networks[args[0]]
      else
        message.network
      end
      network.puts "QUIT :Reconnecting"
    end

    #@doc
    # (superuser only)
    # Shuts down the bot.
    add_command :core, "admin shutdown" do |message,(reason)|
      auth_command :superuser, message
      reason ||= "Shutting down for maintenance"
      CCCB.instance.networking.networks.each do |name,network|
        next unless network.type == :irc
        network.puts "QUIT :#{reason}"
      end
    end
  end
end
