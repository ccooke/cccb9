module CCCB::Settings

  def setting(name)
    unless CCCB.instance.settings.db[self.class] and CCCB.instance.settings.db[self.class].include? name
      raise "No such setting: #{name}" 
    end
    storage[:settings] ||= {}
    if storage[:settings].include? name
      storage[:settings][name]
    else
      storage[:settings][name] = CCCB.instance.settings.db[self.class][name][:default]
    end
  end

  def setting=(name,value)
    storage[:settings][name] = value
  end

  def auth_setting(message,name)
    db = CCCB.instance.settings.db
    case db[self][name][:auth]
    when :superusers
      CCCB.instance.setting("superusers").include? message.from
    when :network
      message.network == @network and @network.setting("trusted").include? message.from
    when :channel
      message.channel == self and 
        message.channeluser.channel == self and
        message.channeluser.is_op?
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

  def add_setting(type,name,auth,default = false)
    klass = SETTING_TARGET[type]
    settings.db[klass] ||= {}
    if settings.all.include? name and not settings.db[klass].include? name
      raise "A setting with that name already exists"
    end
    settings.db[klass][name] = {
      auth: auth,
      default: default
    }
    settings.all[name] = settings.db[klass][name]
  end

  def add_setting_test(type,name,&block)
    klass = SETTING_TARGET[type]
    if klass.instance_methods.include? name and not klass.setting_test? name
      raise "A method named #{name} already exists on #{klass}" 
    end
    klass.instance_exec do
      @setting_tests ||= []
      def self.setting_test?(method)
        @setting_tests.include?(method)
      end

      define_method name, block
      @setting_tests << name
    end
  end

  def module_load
    settings.db ||= {}
    settings.all ||= {}
    
    SETTING_TARGET.values.each do |klass|
      klass.instance_exec do
        include CCCB::Settings
      end
    end

    add_setting :core, "superusers", :superusers, []
    add_setting_test :user, :superuser? do 
      puts "Does #{CCCB.instance.setting("superusers")} include #{self.from.downcase}"
      puts "#{CCCB.instance.setting("superusers").include?(self.from.downcase.to_s).inspect}"
      puts "#{(CCCB.instance.setting("superusers").first == self.from.downcase.to_s).inspect}"
      puts "SF: #{(CCCB.instance.setting("superusers").first.inspect)}"
      puts " F: #{(self.from.downcase).to_s.inspect}"

      CCCB.instance.setting("superusers").include? self.from.downcase.to_s
    end
    setting("superusers") << "ccooke!~ccooke@spirit.gkhs.net".to_sym
    setting("superusers").uniq!
  end

end

