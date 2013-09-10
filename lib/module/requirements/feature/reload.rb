
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
        verbose "Reloading #{code_file}"
        $".delete( code_file )
        begin 
          require code_file
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
      @reload = true
    end

    call_submodules :module_load

    call_submodules :module_start

    self.start if self.respond_to? :start

    #load_hooks config(:codedir)
    
    run_hooks :ready
  end

  def reload_body
    loop do 
      until @reload
        sleep 1
      end
      @reload = false
      clean_reload
    end
  end

  def reload_loop    
    startup
    reload_body
  end

  def clean_reload
    Thread.pass
    @reload_lock.synchronize do
      critical "Reloading client"
      shutdown
      redefine
      startup
      critical "Reload complete"
    end
  end

  def module_load
    @reload_lock = Mutex.new
  end
end

