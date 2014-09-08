module CCCB::Core::FilterHooks
  extend Module::Requirements
  needs :bot
  
  module FilterHookFeatures
    def select_hook_feature?( feature )
      detail2 "Called select_hook_feature( #{feature} )"
      if feature == :core
        true
      else
        self.get_setting("allowed_features", feature.to_s)
      end
    end
  end

  FILTER_CLASSES = [
    CCCB::User,
    CCCB::ChannelUser,
    CCCB::Network,
    CCCB::Message
  ]

  def module_load
    add_setting :core, "allowed_features", default: { "core" => true }
    add_setting :network, "allowed_features", auth: :superuser
    add_setting :channel, "allowed_features", auth: :superuser
    add_setting :user, "allowed_features", auth: :superuser
    set_setting true, "allowed_features", "core"


    add_hook :core, :pre_setting_set do |obj, setting, hash|
      if obj == CCCB.instance and setting == 'allowed_features'
        hash["core"] = true
      end
    end

    FILTER_CLASSES.each do |klass|
      klass.class_exec do 
        include FilterHookFeatures
      end
    end
  end

  def module_start
    allowed = get_setting("allowed_features")
#    hooks.features.keys.map(&:to_s).each do |f|
#      debug "Got feature: #{f}"
#      unless allowed.include? f
#        allowed[f] = false
#      end
#    end
  end

end
