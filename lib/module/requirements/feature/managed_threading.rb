require 'managedthreads'

module Module::Requirements::Feature::ManagedThreading
  extend Module::Requirements

  def module_load
    ManagedThread.default_restart = false
    ManagedThread.default_repeat = false
  end

  def module_unload
    ManagedThread.default_start = false
    ManagedThread.all_threads.map &:stop
  end

  def module_start
    ManagedThread.default_start = true
    ManagedThread.all_threads.map &:start
  end

end




