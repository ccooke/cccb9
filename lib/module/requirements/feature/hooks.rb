require 'thread'
require 'yaml'

module Module::Requirements::Feature::Hooks
  class NoFeature < Exception; end
  extend Module::Requirements
  needs :logging, :managed_threading
  
  def add_hook(feature, hooklist, filter: {}, generator: 0, top: false, unique: false, &block)
    Array(hooklist).each do |hook|
      spam "ADD hook #{hook}" 
      hooks.db[ hook ] ||= []
      call = if generator > 0
        caller_locations(3 + generator,1).first
      else
        caller_locations(3,1).first
      end
      hooks.features[feature] = true
      method = top ? :unshift : :push
      raise "Attempted to redefine a unique hook" if unique and hooks.db[hook].count > 0
      hooks.lock.synchronize do 
        id = hooks.db[hook].count
        hooks.db[ hook ].send(method,
          :id => id,
          :feature => feature,
          :filter => filter,
          :source_file => call.path,
          :source_line => call.lineno,
          :container => call.base_label,
          :code => block
        )
      end
    end
  end

  def remove_hook(feature, hook, source_file, source_line)
    hooks.lock.synchronize do
      match = { feature: feature, source_file: source_file, source_line: source_line }
      hooks.db[hook].delete_if { |h| match.all? { |k,v| h[k] == v } }
    end
  end

  def get_hooks(feature, hook)
    hooks.db[ hook ].select { |h| h[:feature] == feature }
  end

  def schedule_hook hook, *args, &block
    hooks.queue << [ hook, args, block ]
  end

  def get_blocks_for hook, *args
    return [] unless hooks.db.include? hook and hooks.db[hook].count > 0
    hook_list = hooks.lock.synchronize do
      hooks.db[ hook ].select do |i|
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
    end
  end

  def hook_runnable? hook, *args
    count = 0
    detail2 "Runnable #{hook}?"
    yield_hooks(hook,*args) { |i,h| count += 1 }
    detail3 "#{hook} Count: #{count}"
    count > 0
  end

  def run_hook_code hook, item, args
    begin
      if item[:code].call( *args ) == :end_hook_run
        return item      
      end
    rescue Exception => e
      if args.last.respond_to? :to_hash and args.last[:throw_exceptions]
        raise e
      else
        schedule_hook :exception, e, hook, item, args
        if hooks.db.include? :backtrace
          current_dir = Dir.pwd
          short_names = {}
          minimised_backtrace = e.backtrace.map do |l|
            match = l.match %r{^(?:#{current_dir})?(/?lib/)?(?<file>.*?/(?<short_name>[^/]+?).rb):(?<line_number>\d+):in.*$}
            unless short_names.include? match[:file]
              i = 1
              while short_names.values.include?( short_name = match[:short_name] + i.to_s )
                i += 1
              end
              short_name = match[:short_name] + i.to_s
              short_names[match[:file]] = short_name
            end
            "#{short_names[match[:file]]}:#{match[:line_number]}"
          end
          schedule_hook :backtrace, e, short_names, minimised_backtrace, hook, item, args 
        end
      end
    end
  end

  def run_hook hook, item, args, hook_debug
    detail2 "RUN: #{ item[:feature] }:#{ hook }->( #{args} )"
    hook_debug << [ Time.now, item ]
    if hook != :hook_debug_hook
      schedule_hook :hook_debug_hook, hook, [args]
    end

    if args.last.respond_to? :to_hash and args.last[:run_hook_in_thread]
      detail3 "Running hook #{hook} in a new thread"
      Thread.new do
        args.last[:run_hook_in_thread] = false
        run_hook_code hook, item, args
      end
    else
      run_hook_code hook, item, args
      nil
    end
  end

  def run_hooks hook, *args, &block
    hook_stat :run_hooks, hook, args
    spam "hooks: #{hook}->(#{args.join(", ")})"
    hook_debug = []
    hook_stat :hooks_visited, hook_debug
    threads = []
    yield_hooks(hook,*args) do |item|
      thr = run_hook hook, item, args, hook_debug
      threads << thr unless thr.nil?
    end
    sleep 0.1 while threads.any? { |t| t.alive? }
    unless block.nil?
      block.call(hook,hook_debug) 
    end
  end

  def yield_hooks hook, *args
    hook_list = get_blocks_for(hook, *args)
    feature_cache = {}
    while hook_list.count > 0
      item = hook_list.shift
      if feature_cache.include? item[:feature] and feature_cache[item[:feature]] == false
        schedule_hook :"debug_deny_#{item[:feature]}", hook, item
        next 
      end
      next if args.empty?
      next if args.any? { |a|
        begin
          if a.respond_to? :select_hook_feature? 
            feature_cache[item[:feature]] = a.select_hook_feature?(item[:feature])
            if feature_cache[item[:feature]]
              detail3 "Hook #{hook}: ALLOW #{item[:feature]}"
              false
            else
              schedule_hook :"debug_deny_#{item[:feature]}", hook, item
              detail2 "Hook #{hook}: DENY #{item[:feature]}"
              true
            end
          end
        rescue Exception => e
          verbose "Exception while filtering features: #{e.message}"
        end
      }

      yield item, hook
    end
  end

  def hook_stat_dump
    critical "DUMPING HOOK STATES: "
    critical "THREADS: #{Thread.list}"
    Thread.list.each do |t|
      critical "THREAD #{t}: #{t.backtrace}"
    end
    critical hooks.stats.to_yaml
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
      ManagedThread.new :"hook_runner_#{hooks.runners}", start: true do
        hook_stat :runner_id, hook_id
        loop do
          begin
            hook_stat :current, :waiting
            (hook_to_run, args, block) = hooks.queue.pop
            detail2 "RUNNER: #{hook_id}: #{hook_to_run}, #{args}, #{block}"
            hook_stat :current, :processing, hook_to_run, args
            run_hooks hook_to_run, *args, &block
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

