
module Module::Requirements::Feature::CallModuleMethods
  extend Module::Requirements


  def call_submodules(method,*args)
    puts "Subcall #{method}(#{args.join(", ")})" if $DEBUG
    self.class.module_requirements_loader.submodules.select { |a| 
      next if a == self
      a.instance_methods.include? method 
    }.each do |a|
      puts "Call #{a}.#{method}(#{args.join(", ")})" if $DEBUG
      a.instance_method(method).bind(self).(*args)
    end
  end
end


