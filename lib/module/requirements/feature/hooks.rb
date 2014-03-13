require 'thread'
require 'yaml'

module Module::Requirements::Feature::Hooks
  class NoFeature < Exception; end
  extend Module::Requirements
  needs :logging, :managed_threading
  
  def add_hook(feature, hooklist, filter = {}, &block)
    Array(hooklist).each do |hook|
      spam "ADD hook #{hook}" 
      hooks.db[ hook ] ||= []
      call = caller_locations(1,1).first
      hooks.features[feature] = true
      hooks.db[ hook ].push(
        :feature => feature,
        :filter => filter,
        :source_file => call.absolute_path,
        :container => call.base_label,
        :code => block
      )
    end
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
    hook_stat :run_hooks, hook, args
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
    debug "hooks: #{hook}->(#{args.join(", ")})"
    hook_debug = []
    hook_stat :hooks_visited, hook_debug
    feature_cache = {}
    while hook_list.count > 0
      item = hook_list.shift

      next if feature_cache.include? item[:feature] and feature_cache[item[:feature]] == false

      next if args.any? { |a|
        begin
          if a.respond_to? :select_hook_feature? 
            feature_cache[item[:feature]] = a.select_hook_feature?(item[:feature])
            if feature_cache[item[:feature]]
              debug "Hook #{hook}: ALLOW #{item[:feature]}"
              false
            else
              debug "Hook #{hook}: DENY #{item[:feature]}"
              true
            end
          end
        rescue Exception => e
          verbose "Exception while filtering features: #{e.message}"
        end
      }
      spam "RUN: #{ item[:feature] }:#{ hook }->( #{args} )"
      hook_debug << [ Time.now, item ]
      begin
        item[:code].call( *args )
      rescue Exception => e
        schedule_hook :exception, e, hook, item
      end
    end
  end

  def hook_stat_dump
    warning "DUMPING HOOK STATE: "
    warning hooks.stats.to_yaml
  end

  def module_load

    dump_hook_stats = false

    Signal.trap("USR1") do
      dump_hook_stats = true
    end

    hooks.db = {}
    hooks.queue ||= Queue.new
    hooks.runners = 0
    hooks.lock ||= Mutex.new
    hooks.features = {}
    hooks.stats = {}

    ManagedThread.new :hook_stats do
      loop do
        sleep 1
        if dump_hook_stats 
          hook_stat_dump
          dump_hook_stats = false
        end
      end
    end

    add_hook :core, :exception do |exception|
      begin 
        ppdata = ""
        PP.pp(exception.backtrace,ppdata="")
        critical "Exception: #{exception.inspect} #{ppdata}"
      rescue Exception => e
        puts "AWOOGA AWOOGA: Exception in exception handler: #{e} #{e.backtrace.inspect}"
        puts "AWOOGA AWOOGA: Was trying to handle: #{exception} #{exception.backtrace.inspect}"
      end
    end

    global_methods :schedule_hook, :run_hooks
    add_hook_runner
  end

  def hook_stat( name, *args )
    hooks.stats[name] ||= {}
    hooks.stats[name][Thread.current] = {
      time: Time.now,
      args: args
    }
  end

  def add_hook_runner
    hooks.lock.synchronize do
      hook_id = (hooks.runners += 1)
      ManagedThread.new :"hook_runner_#{hooks.runners}" do
        hook_stat :runner_id, hook_id
        loop do
          begin
            hook_stat :current, :waiting
            (hook_to_run, args) = hooks.queue.pop
            hook_stat :current, :processing, hook_to_run, args
            run_hooks hook_to_run, *args
          rescue Exception => e
            hook_stat :exception, 
            stats[:current] = [ :exception, Time.now, e ]
            run_hooks :exception, e
          end
        end
      end
      spam "Initialized hook runner #{hooks.runners}"
    end
  end

end

