require 'thread'

module Module::Requirements::Feature::Reload
  extend Module::Requirements
  needs :hooks, :call_module_methods, :logging

  @@first_startup ||= []
  @@first_startup << true if @@first_startup.empty?

  def shutdown
    run_hooks :reload_pre
    call_submodules :module_unload
  end

  def redefine
    raise "Reload lock is not taken" unless reload.lock.locked?
    reload.errors = []
    saved = $-v
    $-v = nil
    
    self.class.module_requirements_loader.submodules.map { |m| 
      m.name.split('::').last
    }.select { |m|
      m.start_with? 'AutoDependency'
    }.map(&:to_sym).select { |m| 
      self.class.module_requirements_loader.constants.include? m
    }.each do |m|
      debug "Destroying #{m} before reload"
      self.class.module_requirements_loader.class_exec do
        remove_const m
      end
    end

    Gem.clear_paths

    $".select { |f| 
      f.start_with? config(:basedir) 
    }.map { |f| 
      f.split('/') 
    }.sort { |a,b|
      b.count <=> a.count
    }.map { |f| f.join('/') }.each do |code_file|
      begin 
        #if (errors = %x{#{ENV['RUBY_BIN'] || "ruby2.0" } -c #{code_file} 2>&1 }) =~ /Syntax OK/
          debug "Marking #{code_file} for reload"
          $".delete( code_file )
          #require code_file
        #else
        #  err = "Syntax errors in #{code_file} prevent reloading it: #{errors}"
        #  critical err
        #  reload.errors << err
        #end
      rescue Exception => e
        puts "MARK RELOAD EXCEPTION"
        puts e
        pp e.backtrace
      end
    end

    begin
      require 'cccb'
    rescue Exception => e
      puts "RELOAD EXCEPTION"
      puts e
      pp e.backtrace
    end

    $-v = saved
  end

  def startup
    Signal.trap("HUP") do
      reload.queue << true
    end

    Signal.trap("USR2") do
      puts "Begin thread kill"
      Thread.list.each do |thr|
        next if thr == Thread.current
        t = Time.now.to_f
        p Thread.list
        puts ""
        puts "I am about to kill #{thr}"
        Thread.pass
        pp thr.backtrace
        Thread.pass
        thr.kill
        puts "Killing #{thr} took #{ sprintf( "%.7f", Time.now.to_f - t ) }"
      end
    end

    call_submodules :module_load

    begin
      call_submodules :module_test, throw_exceptions: true
    rescue Exception => e
      queue = Module::Requirements::Feature::Logging.class_variable_get(:@@logging_queue)

      until queue.empty?
        (level,message,keys) = queue.pop
        message.each { |m| debug_print level, *m, **keys }
      end
      if @@first_startup.first
        critical "This is the first startup: #{@@first_startup.inspect}"
        critical "Self-Tests failed: #{e.class}:#{e}"
        raise e
      else
        $load_errors << critical( "Self-Tests failed: #{e.class}:#{e} #{e.backtrace}")
      end
    end
    @@first_startup[0] = false

    call_submodules :module_start

    self.start if self.respond_to? :start

    run_hooks :ready
    reload.time = Time.now

  end

  def reload_then(*args, &block)
    Thread.new do
      reply = Queue.new
      reload.queue << reply
      reply.pop
      begin
        block.call(*args)
      rescue Exception => e
        error "Error in reload_then block: #{e}"
        error "BT: #{e.backtrace}"
      end
    end
  end

  def reload_body
    loop do 
      reply = reload.queue.pop
      begin
        clean_reload
      rescue Exception => e
        p e
      end
      reply << "ok" if reply.respond_to? :<<
    end
  end

  def reload_loop    
    startup
    reload.queue = Queue.new
    reload_body
  end

  def clean_reload
    Thread.pass
    detail2 "Obtaining reload lock"
    reload.lock.synchronize do
      detail "Reload locked"
      debug "Reloading client"
      shutdown
      debug "Shutdown done"
      redefine
      debug "redefine done"
      startup
      critical "Client reloaded"
    end
  end

  def module_load
    reload.lock ||= Mutex.new
  end
end

