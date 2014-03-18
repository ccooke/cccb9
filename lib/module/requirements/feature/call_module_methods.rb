
module Module::Requirements::Feature::CallModuleMethods
  extend Module::Requirements
  needs :logging

  def call_submodules(method,*args)
    #cp0 = Time.now.to_f
    #puts "Subcall #{method}(#{args.join(", ")})" if $DEBUG
    self.class.module_requirements_loader.submodules.select { |a| 
      next if a == self
      a.instance_methods.include? method 
    }.each do |a|
      #puts "Call #{a}.#{method}(#{args.join(", ")})" if $DEBUG
      begin
        #cp1 = Time.now.to_f
        a.instance_method(method).bind(self).(*args)
        #cp2 = Time.now.to_f
        #puts("c_sm_m #{method} in #{a} took #{cp2 - cp1}s")
      rescue Exception => e
        critical "Exception calling #{a}.#{method}: #{e}"
      end
    end
    #cp3 = Time.now.to_f
    #puts("c_sm_m TOTAL ELAPSED: #{cp3 - cp0}")
  end
end


