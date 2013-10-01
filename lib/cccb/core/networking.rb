
require 'socket'

module CCCB::Core::Networking
  extend Module::Requirements
  needs :hooks

  def connected?(network)
    networking.networks[name][:state] == :connected
  end

  def net_thread(method, name)
    spam "Starting net_thread #{method} for #{name}"
    loop do
      begin
        networking.networks[name].send(method)
      rescue Exception => e
        schedule_hook :exception, e
      end
    end
  end

  def module_load
    networking.networks ||= {}
    networking.queues ||= {}

    self.servers.each do |name,conf|
      conf[:name] = name.dup
      info "Starting network #{name}"
      networking.networks[name] ||= CCCB::Network.new(conf)

      ManagedThread.new :"networking_recv_#{name}" do
        net_thread :receiver, name
      end
      ManagedThread.new :"networking_send_#{name}" do
        net_thread :sender, name
      end
    end
  end
end

