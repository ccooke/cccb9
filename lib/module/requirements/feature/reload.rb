require 'thread'

module Module::Requirements::Feature::Reload
  extend Module::Requirements
  needs :hooks, :call_module_methods

  def shutdown
    verbose "Hook reload_pre"
    run_hooks :reload_pre
    verbose "c_sm module_unload"
    call_submodules :module_unload
    verbose "c_sm module_unload done"

    #save

    #unload_all_hooks
  end

  def redefine
    Thread.exclusive do
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
          puts "RELOAD EXCEPTION"
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
      block.call(*args)
    end
  end

  def reload_body
    loop do 
      reply = reload.queue.pop
      puts "Start a reload"
      clean_reload
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
    verbose "Obtaining reload lock"
    reload.lock.synchronize do
      verbose "Reload locked"
      debug "Reloading client"
      shutdown
      verbose "Shutdown done"
      redefine
      verbose "redefine done"
      startup
      critical "Client reloaded"
    end
  end

  def module_load
    reload.lock ||= Mutex.new
  end
end

