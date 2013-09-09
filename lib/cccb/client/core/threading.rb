require 'cccb/util/managedthreads'

module CCCB::Client::Core::Threading


  def module_load
    CCCB::Client.extend(ThreadCompartment) 

	  ManagedThread.default_state = :stopped
	  ManagedThread.default_restart = false
  end

  def start
    ManagedThread.all_threads.map &:start
  end
end




