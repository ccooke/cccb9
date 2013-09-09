require 'thread'

module CCCB::Client::Core::Hooks
	provides :hooks
	needs :logging
	
	def add_hook hook, filter = {}, &block
		@hooks[ hook ] ||= []
		call = caller_locations(1,1).first
		@hooks[ hook ].push(
      :filter => filter,
			:source_file => call.absolute_path,
			:container => call.base_label,
			:code => block
		)
	end

	def remove_hooks source, key = :source_file
		@hooks.each do |content|
			content.delete_if { |item| item[key] == source }
		end
	end

	def schedule_hook hook, *args
		@hook_queue << [ hook, args ]
	end

	def run_hooks hook, *args
		unless @hooks.include? hook
			@hooks[ hook ] = []
		end
		hooks = @hooks[ hook ].select do |i|
      if i.include? :filter and i[:filter].respond_to? :all?
        begin 
          i[:filter].all? do |k,v|
            args[0].send( k ) == v
          end
        rescue Exception => e
          false
        end
      else
        true
      end
    end
		spam "hooks: #{hook}->(#{args.join(", ")})"
		begin
			while hooks.count > 0
				item = hooks.shift
				spam "RUN: #{ item[:container] }:#{ hook }"
				item[:code].call( *args )
			end
		rescue Exception => e
			# "(eval):9:in `block (2 levels) in load_hooks'"
			begin
				@hooks[:exception].each do |saviour|
					saviour[:code].call( e, hook, item )
				end
			end

			retry
		end
	end

	def module_load
		@hooks = {}
    @hook_queue ||= Queue.new
		@hook_runners = 0
		@hook_lock = Mutex.new

    add_hook :exception do |exception|
			begin 
        ppdata = ""
				PP.pp(exception.backtrace,ppdata="")
				critical "Exception: #{exception.inspect} #{ppdata}"
			rescue Exception => e
				puts "AWOOGA AWOOGA: Exception in exception handler: #{e} #{e.backtrace.inspect}"
				puts "AWOOGA AWOOGA: Was trying to handle: #{exception} #{exception.backtrace.inspect}"
			end
    end

		global_methods :schedule_hook
    ( 1 + self.servers.count ).times { add_hook_runner }
	end

	def add_hook_runner
		@hook_lock.synchronize do
			@hook_runners += 1
			ManagedThread.new :"hook_runner_#{@hook_runners}" do
				loop do
					begin
						(hook_to_run, args) = @hook_queue.pop
						run_hooks hook_to_run, *args
					rescue Exception => e
						run_hooks :exception, e
					end
				end
			end
			verbose "Initialized hook runner #{@hook_runners}"
		end
	end

end

