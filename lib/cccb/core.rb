
class CCCB
  module Core
    extend Module::Requirements::Loader

    add_feature Module::Requirements::Feature::Hooks
    add_feature Module::Requirements::Feature::Reload
    add_feature Module::Requirements::Feature::Logging
    add_feature Module::Requirements::Feature::ManagedThreading
    add_feature Module::Requirements::Feature::StaticMethods
    add_feature Module::Requirements::Feature::CallModuleMethods
  end
end


