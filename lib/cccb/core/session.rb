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

  def get_setting(name,key=nil)
    return super if name == "identity"
    return super unless registered? and delegated?
    info "Parent is #{get_setting("identity", "parent")}"
    info "Delegated to #{delegated}"
    delegated.get_setting(name,key)
  end

  def set_setting(value,name,key=nil)
    return super if name == "identity" and key == "parent"
    if registered? and delegated?
      delegated.set_setting(value,name,key)
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

  def delegated?
    !!get_setting("identity", "parent")
  end

  def delegated
    nick = get_setting("identity", "parent")
    return self if "#{nick}" == "" 
    network.get_user(nick).delegated
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

  class Incest < Exception; end

  def module_load
    add_setting :core, "session", persist: false
    add_setting :network, "session", auth: :superuser, persist: false
    add_setting :user, "session", auth: :superuser, persist: false

    set_setting false, "session", "authenticated"

    add_setting :user, "identity", auth: :superuser, secret: true, hide_keys: [ "password", "salt" ]
    add_setting :network, "identity", auth: :superuser
    add_setting :core, "identity"

    set_setting false, "identity", "registered"
    set_setting nil, "identity", "parent"

    CCCB::User.class_exec do
      unless included_modules.include? CCCB::Settings::IdentifiedUser
        prepend CCCB::Settings::IdentifiedUser 
      end
    end

    add_hook :session, :pre_setting_set do |obj, setting, hash|
      next unless obj.is_a? CCCB::User
      next unless setting == 'identity' and hash.respond_to? :to_hash and hash.include? 'parent'

      info "Setting parent of #{obj} to #{hash['parent']}"
      
      users = obj.network.users
      parents = []
      next_parent = hash['parent'].downcase

      loop do
        break if next_parent.to_s == ""
        parent_id = next_parent.downcase

        parent = obj.network.get_user( parent_id )

        puts "Is #{parent_id} in #{parents.map { |p| p.nick }}?"
        if parents.any? { |p| p.nick.downcase == parent_id }
          raise Incest.new("Circular parent loops are not allowed") 
        end

        parents << parent
        next_parent = parent.get_setting("identity", "parent")
        info "Found parent for parent chain: #{next_parent}"
      end

      info "Apparently there's no incest here. I found that the parent objects were #{parents}"
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

    add_request :session, /^register\s+(?<password>.*?)\s*$/i do |match, message|
      if message.to_channel?
        if message.user.registered? and message.user.verify_password(match[:password])
          message.user.set_setting(SecureRandom.random_bytes(32), "identity", "password")
        end
        "Denied. Hope that password you just invalidated wasn't yours"
      else
        if match[:password].to_s == ""
          "You need a password to register"
        else
          message.user.register(match[:password])
        end
      end
    end
  end
end

