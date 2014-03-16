module CCCB::Core::AutoReconnect
  extend Module::Requirements
  needs :bot

  def module_load
    auto_reconnect.networks ||= {}
    auto_reconnect.disconnected ||= {}
    set_setting 1, "options", "nick_reconnect_threshold"
    set_setting 60, "options", "nick_reconnect_throttle"

    ManagedThread.new :auto_reconnect, start: true, restart: true do
      loop do
        sleep 10
        CCCB.instance.networking.networks.each do |netname, network|
          auto_reconnect.networks[netname] ||= {}
          unless network.connected?
            debug "Skipping reconnection checks on #{netname}: It is not connected"
            auto_reconnect.disconnected[netname] = true
            next
          end
          if auto_reconnect.disconnected[netname]
            debug "Allowing #{netname} time to finish connecting"
            auto_reconnect.disconnected.delete netname
            next
          end
          debug "Checking for reconnections on #{netname}"
          network.channels.each do |name, channel|
            auto_reconnect.networks[netname][name] ||= Time.now - 86400
            threshold = channel.get_setting("options", "nick_reconnect_threshold").to_i
            if channel.users.count < threshold
              info "Channel #{name} has too few users"
              time = Time.now
              since_last_reconnect = time - auto_reconnect.networks[netname][name]
              info "Since last reconnect: #{since_last_reconnect}"
              if since_last_reconnect > channel.get_setting("options", "nick_reconnect_throttle").to_i
                info "Reconnecting to #{netname}: Too few users in #{name}"
                auto_reconnect.networks[netname][name] = time
                network.puts "QUIT :Reconnecting - only #{channel.users.count} other users in #{name}, when the threshold is #{threshold}"
                break
              end
            end
          end
        end
      end
    end
  end
end
