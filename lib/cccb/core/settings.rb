module CCCB::Settings

  class SettingError < Exception; end
  class NoSuchSettingError < SettingError; end

  def transient_storage
    @___cccb_transient_storage___ ||= {}
  end

  def setting_cache
    @___setting_cache ||= {   
      keys: {},
      delegation: {},
    }
  end

  def clear_setting_cache 
    CCCB.instance.replace_log_tag :wipe_cache
    debug "Clearing settings cache on #{self}: #{@___setting_cache.inspect}"
    @___setting_cache = {
      keys: {},
      delegation: {}
    }
    @___setting_storage_object = nil
  end

  def delegated?
    setting_storage_object != self
  end

  def setting_storage_object
    return @___setting_storage_object unless @___setting_storage_object.nil?
    target = get_local_setting("identity", "parent")
    spam "Redirection is to #{target.inspect}"
    @___setting_storage_object = CCCB.instance.find_setting_storage_object(self, target)
  end

  def setting_object(name)
    if setting_cache[:delegation].include? name
      setting_cache[:delegation][name]
    else
      target = if setting_option(name, :local) or
         get_local_setting("local_settings",name) or
         ! delegated?
      then
        spam "is local"
        self
      else
        object = setting_storage_object
        spam "is delegated to #{object}"
        object
      end
      debug "Caching delegation for #{self}.#{name} => #{target}"
      setting_cache[:delegation][name] = target
    end
  end

  def get_setting(name,key=nil)
    CCCB.instance.add_log_tag :get
    CCCB.instance.add_log_tag stage: :init
    debug "#{self}.get_setting(#{name},#{key})"
    if (target = setting_object(name)) == self
      spam "Fetching local object #{self}::#{name}"
      get_local_setting(name,key)
    else
      spam "Fetching delegated object #{name}"
      CCCB.instance.replace_log_tag stage: :delegate
      target.get_setting(name,key)
    end
  end

  def get_local_setting(name,key=nil)
    CCCB.instance.replace_log_tag stage: :local
    if key
      cache_key = "#{name}::#{key}"
      if setting_cache[:keys].include? cache_key
        spam "cache hit"
        setting_cache[:keys][cache_key]
      else
        spam "cache miss"
        if ( result = get_local_setting_uncached(name,key) ).nil?
          begin
            if CCCB::SETTING_CASCADE.include? self.class
              parent = CCCB::SETTING_CASCADE[self.class].call(self) 

              spam "Cascade to #{parent.inspect}.get_setting(#{name},#{key})"
              CCCB.instance.replace_log_tag stage: :inherit
              result = parent.get_setting(name, key)
            end
          rescue NoSuchSettingError => e
          end
          # never cache a nil
        else
          spam"cache SET: #{self}::#{cache_key} = #{result.inspect}"
          setting_cache[:keys][cache_key] = result
        end
        detail "Return result #{result.inspect}"
        result
      end
    else
      get_local_setting_uncached(name,key)
    end
  end

  def get_local_setting_uncached(name,key=nil)
    CCCB.instance.replace_log_tag stage: :uncached
    settings = if setting_option( name, :persist )
      spam "is persistent"
      if name == "session"
        spam "In #{self}, found session to be persistant: #{CCCB.instance.settings.db[self.class][name]}"
      end
      storage[:settings] ||= {}
    else
      spam "is transient"
      transient_storage
    end
    spam "Getting setting #{self}.#{name}"
    db = CCCB.instance.settings.db

    cursor = if settings.include? name and !settings[name].nil?
      settings
    elsif db[self.class].include? name
      debug "Defaulted #{name},#{key} on #{self}"
      settings[name] = Marshal.load( Marshal.dump( setting_option(name, :default) ) )
      settings
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
    

    result
  end

  def setting?(name,key=nil)
    data = get_setting(name)
    if key
      get_setting(name)[key].nil?
    else
      get_setting(name).nil?
    end
  end

  def default_setting(value, name, key)
    if get_setting(name,key).nil?
      set_setting(value,name,key)
    end
  end

  def set_setting(value,name,key=nil)
    CCCB.instance.add_log_tag :set
    if (target = setting_object(name)) == self
      set_local_setting(value,name,key)
    else
      target.set_setting(value,name,key)
    end
  end

  def set_local_setting(value, name, key=nil)
    CCCB.instance.replace_log_tag stage: :local
    translation = {}
    CCCB.instance.settings.lock.synchronize do 
      spam "Setting #{self}.#{name}[#{key}] to #{value}"
      current = get_setting(name, key)
      cursor = if setting_option( name, :persist )
        detail "is in persistant storage"
        storage[:settings] ||= {}
      else
        detail "is transient"
        transient_storage
      end

      temp = if key
        { key => value }
      else
        value
      end
      detail "Temp sent as #{temp.inspect}"
      run_hooks :pre_setting_set, self, name, temp, translation, throw_exceptions: true
      detail "Temp returned as #{temp.inspect}"
      unless cursor.include? name
        cursor[name] = Marshal.load( Marshal.dump( setting_option(name, :default) ) )
        debug "Defaulting to #{cursor[name]}"
      end
      
      clear_setting_cache if setting_option(name,:clear_cache_on_set)
      if temp.respond_to? :to_hash
        temp.each do |k,v|
          saved = cursor[name].include? k ? cursor[name][k] : nil
          cache_key = "#{name}::#{key}"
          setting_cache[:keys].delete( cache_key )
          if v.nil?
            detail "Deleting key #{k.inspect}"
            cursor[name].delete k
          else
            detail "Setting key #{k} to #{v}"
            cursor[name][k] = v
          end
          schedule_hook :setting_set, self, name, k, saved, v
        end
      elsif current.respond_to? :to_hash
        raise "A hash setting may only be replaced with a hash"
      else
        detail "Setting to #{temp.inspect}"
        cursor[name] = temp
        schedule_hook :setting_set, self, name, nil, current, v
      end
    end
    return translation
  end

  def setting_option(setting,option)
    begin
      opt = if CCCB.instance.settings.db[self.class].include? setting
        CCCB.instance.settings.db[self.class][setting][option]
      else
        spam "Setting #{setting} does not exist on #{self.class}"
        nil
      end
      spam "option #{option} = #{opt}"
      opt
    rescue Exception => e
      pp "CLASS: #{self.class} ", CCCB.instance.settings.db
      sleep 1
      pp e
      pp e.backtrace
      STDOUT.flush
      raise e
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

class CCCB::Message
  def __setting_target()
    if self.to_channel?
      self.channel
    elsif ! self.user.nil?
      self.user
    else 
      self.network
    end
  end
  private :__setting_target

  def get_setting(*args)
    __setting_target.get_setting(*args)
  end

  def set_setting(*args)
    __setting_target.set_setting(*args)
  end
end

module CCCB::Core::Settings
  extend Module::Requirements
  
  needs :persist

  class Incest < Exception; end

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

  DEFAULT_SETTING_OPTIONS = %i{ auth default secret persist hide_keys clear_cache_on_set local}
  def get_default_setting_option(type,key)
    case key
    when :auth; DEFAULT_AUTH_BY_TYPE[type]
    when :default; {}
    when :secret; false
    when :persist; true
    when :hide_keys; []
    when :clear_cache_on_set; false
    when :local; false
    end
  end

  def add_setting(type,name,**options)
    type = SETTING_TARGET.keys if type == :all
    Array(type).each do |t|
      klass = SETTING_TARGET[t]
      settings.db[klass] ||= {}
      current_options = settings.db[klass][name] || {}
      option_keys = DEFAULT_SETTING_OPTIONS + current_options.keys + options.keys
      new_options = option_keys.uniq.each_with_object({}) do |key,hash|
        hash[key] = if options.include? key
          options[key]
        elsif current_options.include? key
          current_options[key]
        else
          get_default_setting_option(type,key)
        end
      end

      spam "Updated setting #{klass}[#{name}] => #{new_options}"
      settings.db[klass][name] = Marshal.load( Marshal.dump( new_options ) )
    end
  end
  alias_method :alter_setting, :add_setting

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

  def find_setting_storage_object(object, target)
    if target.nil?
      object
    else
      target = case object
      when CCCB::User
        object.network.get_user(target)
      when CCCB::Channel
        object.network.get_channel(target)
      when CCCB::ChannelUser
        object.network.get_user(target)
      when CCCB::Network
        CCCB.instance.networking.networks[target]        
      when CCCB
        # The core may not be delegated. Yet.
        # Delegate to another instance of CCCB!
        self
      else
        raise "Objects without settings cannot be delegated"
      end
    end
  end

  def module_load
    settings.lock ||= Mutex.new
    settings.db ||= {}
    settings.default ||= Hash.new { {} }
    settings.cache = {}

    persist.store.define CCCB, :class
    persist.store.define CCCB::Network, :name
    persist.store.define CCCB::User, :network, :id
    persist.store.define CCCB::Channel, :network, :name 

    SETTING_TARGET.values.each do |klass|
      klass.instance_exec do
        include CCCB::Settings
      end
    end

    # Clear all caches
    count = 0

    settings_objects = ObjectSpace.each_object.select { |o| o.is_a? CCCB::Settings }
    unless settings_objects.nil?
      settings_objects.each do |o|
        count += 1
        detail "Clear settings cache for #{o}"
        o.clear_setting_cache
      end
    end
      
    verbose "Cleared settings cache on #{count} objects"

    add_hook :core, :pre_setting_set do |obj, setting, hash|
      next unless setting == 'identity' and hash.respond_to? :to_hash and ! hash['parent'].nil?
      verbose "Setting parent of #{obj} to #{hash['parent']}"
      
      parents = [ obj ]
      next_parent = find_setting_storage_object(obj, hash['parent'])
      
      loop do
        if next_parent == parents.last
          spam "Found an orphan"
          break
        end
        if parents.any? { |p| p.name == next_parent.name }
          raise Incest.new("Circular parent loops are not allowed") 
        end
        parents << next_parent
        next_parent = next_parent.setting_storage_object
      end
        
    end

    # local_settings must be the first setting defined
    add_setting :all, "local_settings", 
      clear_cache_on_set: true,
      default: { "local_settings" => true, "identity" => true},
      local: true
    add_setting :all, "identity", 
      clear_cache_on_set: true, 
      auth: :superuser, 
      default: { "parent" => nil },
      local: true
  end

  def module_test
    test_setting_name = "test_setting_#{CCCB.instance.get_log_id}"
    add_setting :core, test_setting_name, auth: :superuser
    random = 10.times.each_with_object({}) { |i,o| o["key#{i}"] = rand() }
    random.each { |k,v| set_setting v, test_setting_name, k }
    key = random.keys[(rand() * random.length).to_i]
    value = get_setting( test_setting_name, key )
    raise "Set/Get name,key broken: setting[#{key}]=#{value} != random[#{key}]=#{random[key]}" unless value == random[key]
    raise "Set/Get name broken" unless get_setting(test_setting_name) == random
    settings.db[CCCB].delete test_setting_name
  end
end

