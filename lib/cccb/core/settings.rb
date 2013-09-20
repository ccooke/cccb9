module CCCB::Settings

  class SettingError < Exception; end

  def get_setting(name,key=nil)
    storage[:settings] ||= {}
    db = CCCB.instance.settings.db

    parent = if CCCB::SETTING_CASCADE.include? self.class
      CCCB::SETTING_CASCADE[self.class].call(self) 
    end

    cursor = if storage[:settings].include? name
      storage[:settings]
    elsif db[self.class].include? name
      storage[:settings][name] = db[self.class][name][:default].dup
    else
      raise SettingError.new("No such setting #{name}")
    end

    result = if cursor.nil?
      nil
    elsif cursor[name].nil?
      nil
    elsif key
      cursor[name][key]
    else
      cursor[name]
    end

    if result.nil? 
      if parent
        parent.get_setting(name, key)
      end
    else
      result
    end
  end

  def setting?(name,key=nil)
    data = get_setting(name)
    if key
      !!get_setting(name)[key]
    else
      !!get_setting(name) 
    end
  end

  def set_setting(name, value, key=nil)
    current = get_setting(name, key)
    cursor = storage[:settings]
    if key
      cursor = cursor[name]
      if value.nil?
        return cursor.delete(key)
      end
      name = key
    end
    cursor[name] = value
    schedule_hook :setting_set, self, name, current, value
  end

  def auth_setting(message,name)
    db = CCCB.instance.settings.db
    return true if message.user.superuser?
    case db[self.class][name][:auth]
    when :network
      message.network == @network and @network.get_setting("trusted").include? message.from
    when :channel
      message.channel == self and
        message.channeluser.channel == self and
        message.channeluser.is_op?
    when :user
      message.user.nick == self.nick
    else
      super
    end
  end

end

module CCCB::Core::Settings
  extend Module::Requirements
  
  needs :persist, :bot

  SETTING_TARGET = {
    :core => CCCB,
    :channel => CCCB::Channel,
    :network => CCCB::Network,
    :user => CCCB::User,
    :channeluser => CCCB::ChannelUser
  }

  SETTING_CASCADE = {
    CCCB::Channel => Proc.new { |obj| obj.network },
    CCCB::Network => Proc.new { CCCB.instance }
  }

  def add_setting(type,name,auth,default = false)
    klass = SETTING_TARGET[type]
    settings.db[klass] ||= {}
    settings.db[klass][name] = {
      auth: auth,
      default: default
    }
  end

  def add_setting_method(type,name,&block)
    klass = SETTING_TARGET[type]
    if klass.instance_methods.include? name and not klass.setting_method? name
      raise "A method named #{name} already exists on #{klass}" 
    end
    klass.instance_exec do
      @setting_methods ||= []
      def self.setting_method?(method)
        @setting_methods.include?(method)
      end

      define_method name, block
      @setting_methods << name
    end
  end

  def module_load
    settings.db ||= {}
    settings.default ||= Hash.new { {} }
    
    SETTING_TARGET.values.each do |klass|
      klass.instance_exec do
        include CCCB::Settings
      end
    end

    add_setting :core, "superusers", :superusers, []
    add_setting :user, "options", :user, {}
    add_setting :channel, "options", :channel, {}
    add_setting :network, "options", :superusers, {}
    add_setting :core, "options", :superusers, {}

    add_setting_method :user, :superuser? do
      CCCB.instance.get_setting("superusers").include? self.from.to_s.downcase
    end
    
    add_request /^\s*superuser\s+override\s*(?<password>.*?)\s*$/ do |match, message|
      password_valid = (match[:password] == CCCB.instance.superuser_password)
      if message.to_channel?
        if password_valid
          CCCB.instance.superuser_password = (1..32).map { (rand(64) + 32).chr }.join
        end
        "Denied. And don't try to use that password again."
      else
        p [ match[:password], CCCB.instance.superuser_password ]
        if password_valid
          get_setting("superusers") << message.from.downcase.to_s
          "Okay, you are now a superuser"
        else
          "Denied"
        end
      end
    end

    add_request /^\s*superuser\s+resign\s*$/ do |match, message|
      if message.user.superuser?
        get_setting("superusers").delete message.from.downcase.to_s
        "Removed you from the superuser list."
      else
        "You weren't a superuser in the first place."
      end
    end
  end
end

