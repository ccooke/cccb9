
module CCCB::Client::Core::CallSubmodules
	provides :call_submodules
	needs :hooks

	def call_submodules(method,*args)
    puts "Subcall #{method}(#{args.join(", ")})" if $DEBUG
		self.class.submodules_in_order.select { |a| 
			next if a == self
			a.instance_methods.include? method 
		}.each do |a|
      puts "Call #{a}.#{method}(#{args.join(", ")})" if $DEBUG
			a.instance_method(method).bind(self).(*args)
		end
	end
end


