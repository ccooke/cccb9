
require 'socket'

module CCCB::Core::Networking
  extend Module::Requirements
  provides :networking
  needs :hooks

  def connected?(network)
    @network[name][:state] == :connected
  end

  def net_thread(method, name)
    debug "Starting net_thread #{method} for #{name}"
    loop do
      begin
        @network[name].send(method)
      rescue Exception => e
        schedule_hook :exception, e
      end
    end
  end

  def module_load
    @network = {}
    @queues = {}

    self.servers.each do |name,conf|
      conf[:name] = name.dup
      @network[name] = CCCB::Network.new(conf)

      ManagedThread.new :"networking_recv_#{name}" do
        net_thread :receiver, name
      end
      ManagedThread.new :"networking_send_#{name}" do
        net_thread :sender, name
      end
    end
  end
end

