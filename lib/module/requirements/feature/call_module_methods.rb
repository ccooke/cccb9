
module Module::Requirements::Feature::CallModuleMethods
  extend Module::Requirements
  needs :logging

  def call_submodules(method,*args)
    puts "Subcall #{method}(#{args.join(", ")})" if $DEBUG
    self.class.module_requirements_loader.submodules.select { |a| 
      next if a == self
      a.instance_methods.include? method 
    }.each do |a|
      puts "Call #{a}.#{method}(#{args.join(", ")})" if $DEBUG
      begin
        a.instance_method(method).bind(self).(*args)
      rescue Exception => e
        critical "Exception calling #{a}.#{method}: #{e}"
      end
    end
  end
end


