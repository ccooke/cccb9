
module Module::Requirements::Feature::StaticMethods
  extend Module::Requirements

  def define_static_methods(obj_from, obj_to, *methods)
    methods.each do |method|
      #pp( from: obj_from, to: obj_to, method: method )
      raise obj_from.send(method) unless obj_from.respond_to? method
      obj_to.instance_exec(method,obj_from,Thread.current[:feature_store]) do |m,o,caller_store|
          puts "Static method shim: #{self}.#{m} becomes #{o}.#{m}" if $DEBUG
          define_method m do |*args|
            o.send( m, *args )
          end
      end
    end
  end

  def global_methods(*methods)
    define_static_methods(self, Object, *methods)
  end
  
end

