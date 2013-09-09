
module Module::Requirements::Feature::Reload
  extend Module::Requirements
  needs :hooks

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

      Gem.clear_paths

      files = $".select { |f| 
        f.start_with? config(:basedir) 
      }.map { |f| 
        f.split('/') 
      }.sort { |a,b|
        b.count <=> a.count
      }.map { |f| f.join('/') }.each do |code_file|
        critical "Reloading #{code_file}"
        $".delete( code_file )
        Kernel.load( code_file )
      end

      $-v = saved
      self.class.class_exec do
        include CCCB::Core
      end
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

  def reload_loop    
    startup
    loop do 
      sleep 1 until @reload
      @reload = false
      reload
    end
  end

  def reload
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

