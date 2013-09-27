module CCCB::Settings

  class SettingError < Exception; end

  def transient_storage
    @___cccb_transient_storage___ ||= {}
  end

  def get_setting(name,key=nil)
    settings = if setting_option( name, :persist )
      spam "Get #{self}.#{name} is persistant storage #{setting_option(name,:persist).inspect}"
      if name == "session"
        info "In #{self}, found session to be persistant: #{CCCB.instance.settings.db[self.class][name]}"
      end
      storage[:settings] ||= {}
    else
      spam "Get #{self}.#{name} is transient"
      transient_storage
    end
    debug "Getting setting #{self}.#{name} got #{settings.inspect}"
    db = CCCB.instance.settings.db

    parent = if CCCB::SETTING_CASCADE.include? self.class
      CCCB::SETTING_CASCADE[self.class].call(self) 
    end

    debug "get_setting( #{name}, #{key.inspect} ) on #{self}"
    cursor = if settings.include? name and !settings[name].nil?
      settings
    elsif db[self.class].include? name
      debug "Defaulted #{name},#{key} on #{self}"
      settings[name] = Marshal.load( Marshal.dump( setting_option(name, :default) ) )
      settings
    else
      raise SettingError.new("No such setting #{name} on #{self}")
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
      begin
        if parent
          parent.get_setting(name, key)
        end
      rescue SettingError => e
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

  def set_setting(value, name, key=nil)
    current = get_setting(name, key)
    cursor = if setting_option( name, :persist )
      spam "Set #{self}.#{name} is persistant storage #{setting_option(name,:persist).inspect}"
      storage[:settings]
    else
      spam "Set #{self}.#{name} is transient"
      transient_storage
    end
    debug "Setting setting #{self}.#{name} got #{cursor.inspect}"
    saved_name = name
    translation = {}
    return_val = if key
      cursor = cursor[name]
      temp = { key => value }
      run_hooks :pre_setting_set, self, name, temp, translation, throw_exceptions: true
      temp.each do |k,v|
        if v.nil?
          debug "Deleting #{self}.#{name}[#{k}]"
          cursor.delete k
          new_value = get_setting(name,k)
          schedule_hook :setting_set, self, saved_name, key, current, new_value
        else
          debug "Setting #{self}.#{name}[#{k}] = #{v}"
          cursor[k] = v
        end
      end
    else
      run_hooks :pre_setting_set, self, name, value, translation, throw_exceptions: true
      debug "Setting #{self}.#{name} = #{value.inspect}"
      cursor[name] = value
      translation
    end
    schedule_hook :setting_set, self, saved_name, key, current, value
    translation
  end

  def setting_option(setting,option)
    spam "Get option #{self}.#{setting}.#{option}"
    if CCCB.instance.settings.db[self.class].include? setting
      CCCB.instance.settings.db[self.class][setting][option]
    end
  end

  def auth_reject_reason
    @___auth_reject_reason
  end

  def auth_setting(message,name)
    @___auth_reject_reason = "You are not a superuser"
    return true if message.user.superuser?
    case setting_option(name, :auth)
    when :network
      @___auth_reject_reason = "You are not trusted on #{@network}"
      message.network == @network and @network.get_setting("trusted").include? message.from
    when :channel
      @___auth_reject_reason = "You are not a channel operator in #{self}"
      message.channel == self and
        message.channeluser.channel == self and
        message.channeluser.is_op?
    when :user
      @___auth_reject_reason = "You are not #{self.nick}"
      message.user.nick == self.nick
    else
      begin 
        super
      rescue NoMethodError
      end
    end
  end

end

module CCCB::Core::Settings
  extend Module::Requirements
  
  needs :persist

  SETTING_TARGET = {
    :core => CCCB,
    :channel => CCCB::Channel,
    :network => CCCB::Network,
    :user => CCCB::User,
    :channeluser => CCCB::ChannelUser
  }

  SETTING_CASCADE = {
    CCCB::User => Proc.new { |obj| obj.network },
    CCCB::Channel => Proc.new { |obj| obj.network },
    CCCB::Network => Proc.new { CCCB.instance }
  }

  DEFAULT_AUTH_BY_TYPE = {
    :core => :superuser,
    :network => :superuser,
    :channel => :channel,
    :channeluser => :channel,
    :user => :user,
  }

  def add_setting(type,name,options = {})
    options[:auth] ||= DEFAULT_AUTH_BY_TYPE[type]
    options[:default] ||= {}
    options[:secret] ||= false
    options[:persist] = true unless options.include? :persist
    options[:hide_keys] ||= []


    klass = SETTING_TARGET[type]
    settings.db[klass] ||= {}
    settings.db[klass][name] = options.dup
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

    
  end
end

