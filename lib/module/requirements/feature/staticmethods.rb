
class Object
  def metaclass
    class << self; self; end
  end
end

module CCCB::Client::Core::StaticMethods
  provides :static_methods

  def static_methods(obj_from, obj_to, *methods)
    methods.each do |method|
      #pp( from: obj_from, to: obj_to, method: method )
      raise obj_from.send(method) unless obj_from.respond_to? method
      obj_to.instance_exec(method,obj_from) do |m,o|
          puts "Static method shim: #{self}.#{m} becomes #{o}.#{m}" if $DEBUG
          define_method m do |*args|
            o.send( m, *args )
          end
      end
    end
  end

  def global_methods(*methods)
    static_methods(self, Object, *methods)
  end

end

