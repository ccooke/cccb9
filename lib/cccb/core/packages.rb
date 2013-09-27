module CCCB::Core::Packages
  extend Module::Requirements
  needs :bot, :session

  def module_load
    add_setting :channel, "packages", auth: :superuser, default: [], persist: false
    add_setting :channel, "protected", auth: :superuser
    add_setting :network, "protected"
    set_setting true, "options", "bombs_armed"

    networking.networks.each do |name,network|
      info network.nick
      info network.get_user(network.nick)
      info network.user
      network.set_setting true, "protected", network.user.id
    end

    irc_nick = /[-A-Za-z0-9_^%`]+/

    verbs = /(?<verb>hands|gives)/
    target = /\s+(?<target>#{irc_nick})\s+/
    package = /a suspicious package\s*/
    
    add_hook :packages, :message do |message|
      next unless message.ctcp? and message.ctcp == :ACTION
      next unless message.to_channel?
      next unless match = message.ctcp_text.match( /^\s*#{verbs}#{target}#{package}/i )

      if message.to_channel? and target = message.channel.user_by_name(match[:target])

        if message.channel.get_setting("protected",target.id)
          target = message.user.id
        end

        if match[:verb].to_s.downcase == 'gives' and message.user.authenticated?
          package = {
            :fuse => 30,
            :type => :real,
          }
        else
          package = {
            :fuse => 120 - rand( 80 ),
            :type => :dud,
          }
        end
        
        package[:target] = target
        package[:time] = 0
        package[:display] = true

        channel = message.channel
        channel.get_setting("packages") << package

        ManagedThread.new :"bomb_timer_#{message.channel}", repeat: 1, start: true, restart: true do
          if not channel.get_setting("options", "bombs_armed")
            channel.set_setting([], "packages")
            channel.msg "*fizzle*"
            self.kill 
          end
          
          time = Time.now
          packages = channel.get_setting("packages")
          self.kill if packages.empty?

          packages.each do |pkg|

            if pkg[:display] or time - pkg[:time] >= ( 0.6 * pkg[:fuse] )
              if pkg[:time] != 0
                pkg[:fuse] -= ( time - pkg[:time] )
              end
              pkg[:display] = false

              if pkg[:fuse] < 0
                if pkg[:type] == :dud
                  channel.msg "#{pkg[:target]}: BOOM!"
                elsif pkg[:type] == :real
                  channel.network.puts "KICK #{channel} #{pkg[:target]} *BOOM*"
                end
                
                packages.delete(pkg)
              else
                channel.msg "#{pkg[:target]}: " + case pkg[:fuse]
                  when 0..10 then "TICKTICKTICKTICK"
                  when 11..25 then "Tick Tick Tick"
                  when 26..50 then "Tick.. Tick.."
                  when 51..100 then "tick...   tick..."
                  else "tick..."
                end

                pkg[:time] = time
              end
            end
          end
        end

        nil
      end
    end

    add_hook :packages, :message do |message|
      next unless message.ctcp? and message.ctcp == :ACTION
      next unless message.to_channel?
      next unless match = message.text.match( /^.*\spackage(?:\s|\s.*\s)to (?<target>#{irc_nick})/i )

      message.channel.get_setting("packages").each do |pkg|
        if pkg[:type] == :dud and new = message.channel.user_by_name(match[:target])
          pkg[:target] = new
          pkg[:fuse] -= 15
          pkg[:display] = true
        else
          message.reply "And yet, you still have it"
        end
      end
      nil
    end

    add_help(
      :packages,
      "hand_package",
      "Suspicious packages. Guaranteed safe",
      [
        "To trigger a mild explosion, say: ",
        "'/me hands <nick> a suspicious package'",
        "The current holder of the package can",
        "attempt to pass it on to somoene else",
        "by saying any action (using /me) that",
        "includes the words 'package' followed",
        "by 'to' and the nick of somoene present."
      ]
    )

    add_help(
      :packages,
      "give_package",
      "Suspicious packages. Explosive.",
      [
        "When 'given' a package, the target cannot",
        "pass it on to anyone else and will be ",
        "kicked from the channel when the time runs",
        "out. "
      ],
      :ops
    )

    add_help(
      :packages,
      "package_admin",
      "Enable and disable the packages",
      [
        "To disable the package bombs, make a request",
        "saying 'disarm the bombs'. To re-enable them,",
        "request 'arm the bombs'. Disabling bombs will",
        "stop any bombs currently in use."
      ],
      :superuser
    )
  end
end
