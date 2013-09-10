require 'thread'

module Module::Requirements::Feature::Hooks
  extend Module::Requirements
  needs :logging, :managed_threading
  
  def add_hook hook, filter = {}, &block
    spam "ADD hook #{hook}" 
    hooks.db[ hook ] ||= []
    call = caller_locations(1,1).first
    hooks.db[ hook ].push(
      :filter => filter,
      :source_file => call.absolute_path,
      :container => call.base_label,
      :code => block
    )
  end

  def remove_hooks source, key = :source_file
    hooks.db.each do |content|
      content.delete_if { |item| item[key] == source }
    end
  end

  def schedule_hook hook, *args
    hooks.queue << [ hook, args ]
  end

  def run_hooks hook, *args
    unless hooks.db.include? hook
      hooks.db[ hook ] = []
    end
    hook_list = hooks.db[ hook ].select do |i|
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
      while hook_list.count > 0
        item = hook_list.shift
        spam "RUN: #{ item[:container] }:#{ hook }"
        item[:code].call( *args )
      end
    rescue Exception => e
      begin
        hooks.db[:exception].each do |saviour|
          saviour[:code].call( e, hook, item )
        end
      end

      retry
    end
  end

  def module_load

    hooks.db = {}
    hooks.queue ||= Queue.new
    hooks.runners = 0
    hooks.lock ||= Mutex.new

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
    hooks.lock.synchronize do
      hooks.runners += 1
      ManagedThread.new :"hook_runner_#{hooks.runners}" do
        loop do
          begin
            (hook_to_run, args) = hooks.queue.pop
            run_hooks hook_to_run, *args
          rescue Exception => e
            run_hooks :exception, e
          end
        end
      end
      spam "Initialized hook runner #{hooks.runners}"
    end
  end

end

