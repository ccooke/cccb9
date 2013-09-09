
module Module::Requirements::Feature::Reload
  extend Module::Requirements
  needs :hooks

  def shutdown
    ManagedThread.all_threads.map &:halt
    run_hooks :reload_pre

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
        include CCCB::Client::Core
      end
    end
  end

  def startup
    call_submodules :module_load
    run_hooks :init

    #load_hooks config(:codedir)
    
    run_hooks :reload_post
    ::ManagedThread.all_threads.map &:restart

    Signal.trap("HUP") do
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

