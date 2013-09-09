require 'managedthreads'

module Module::Requirements::Feature::ManagedThreading
  extend Module::Requirements

  def module_load
    ManagedThread.default_state = :stopped
    ManagedThread.default_restart = false
  end

  def start
    ManagedThread.all_threads.map &:start
  end
end




