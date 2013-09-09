require 'managedthreads'

module Module::Requirements::Feature::ManagedThreading
  extend Module::Requirements

  def module_load
    ManagedThread.default_restart = false
  end

  def module_unload
    ManagedThread.default_state = :stopped
    ManagedThread.all_threads.map &:stop
  end

  def module_start
    ManagedThread.default_state = :started
    ManagedThread.all_threads.map &:start
  end

end




