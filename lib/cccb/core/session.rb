require 'digest/sha2'
require 'securerandom'

module CCCB::Settings::IdentifiedUser
  def auth_setting(message, name)
    if message.user.superuser? 
      true
    elsif registered? and ( setting_option(name,:auth)==:user or name == 'identity' or name == 'session')
      @___auth_reject_reason = "That user account is registered and you are not logged in"
      get_setting("session", "authenticated")
    else
      super
    end
  end

  def verify_password(password)
    return false unless registered?

    salt = get_setting("identity", "salt")
    hash = Digest::SHA256.hexdigest(password+salt)

    hash == get_setting("identity", "password")
  end

  def registered?
    get_setting("identity", "registered")
  end

  def register(password)
    if registered?
      if verify_password(password)
        set_setting true, "session", "authenticated"
        "OK"
      else
        "Denied"
      end
    else
      set_setting true, "session", "authenticated"
      set_setting true, "identity", "registered"
      set_setting password, "identity", "password"
      "You are now registered"
    end
  end

  def authenticated?
    return false unless registered?
    get_setting("session", "authenticated")
  end
end

module CCCB::Core::Session
  extend Module::Requirements

  needs :bot

  def module_load
    add_setting :user, "session", persist: false, 
      auth: :superuser, 
      default: { "authenticated" => false },
      local: true
    add_setting :user, "privs", auth: :network
    alter_setting :user, "identity", 
      secret: true, 
      hide_keys: [ "password", "salt" ],
      default: settings.db[CCCB::User]["identity"][:default].merge( { registered: false } )

    CCCB::User.class_exec do
      unless included_modules.include? CCCB::Settings::IdentifiedUser
        prepend CCCB::Settings::IdentifiedUser 
      end
    end

    add_hook :session, :pre_setting_set do |obj, setting, hash|
      next unless obj.is_a? CCCB::User
      next unless setting == 'identity' and hash.respond_to? :to_hash and hash.include? 'password'

      hash['salt'] = SecureRandom.base64(32)
      hash['password'] = Digest::SHA256.hexdigest(hash['password'] + hash['salt'])
    end

    add_hook :session, :ctcp_REGISTER do |message|
      next if message.to_channel?
      if ctcp_params.first.to_s == ""
        "You need a password to register"
      else
        message.user.register(message.ctcp_params.first)
      end
    end

    add_command :session, "register" do |message, args|
      message.reply( if message.to_channel?
        if message.user.registered? and message.user.verify_password(args[0].join(" "))
          message.user.set_setting(SecureRandom.random_bytes(32), "identity", "password")
        end
        "Denied. Hope that password you just invalidated wasn't yours"
      else
        if args[0].to_s == ""
          "You need a password to register"
        else
          message.user.register(args.join(" "))
        end
      end )
    end
  end
end

