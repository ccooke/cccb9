
module Module::Requirements::Feature::Reload
  extend Module::Requirements
  needs :hooks, :call_module_methods

  def shutdown
    run_hooks :reload_pre
    call_submodules :module_unload

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
          if (errors = %x{#{ENV['RUBY'] || "ruby2.0" } -c #{code_file} 2>&1 }) =~ /Syntax OK/
            debug "Reloading #{code_file}"
            $".delete( code_file )
            require code_file
          else
            err = "Syntax errors in #{code_file} prevent reloading it: #{errors}"
            critical err
            reload.errors << err
          end
        rescue Exception => e
          puts "RELOAD EXCEPTION"
          puts e
          pp e.backtrace
        end
      end

      $-v = saved
    end
  end

  def startup
    Signal.trap("HUP") do
      reload.now = true
    end

    call_submodules :module_load

    call_submodules :module_start

    self.start if self.respond_to? :start

    #load_hooks config(:codedir)
    
    run_hooks :ready
  end

  def reload_then(*args, &block)
    Thread.new do
      reload.now = true
      sleep 1 until reload.now == false
      block.call(*args)
    end
  end

  def reload_body
    loop do 
      until reload.now
        sleep 1
      end
      reload.now = false
      clean_reload
    end
  end

  def reload_loop    
    startup
    reload.now = false
    reload_body
  end

  def clean_reload
    Thread.pass
    reload.lock.synchronize do
      debug "Reloading client"
      shutdown
      redefine
      startup
      critical "Client reloaded"
    end
  end

  def module_load
    reload.lock = Mutex.new
  end
end

