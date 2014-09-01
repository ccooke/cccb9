module CCCB::Core::Ops
  extend Module::Requirements

  needs :session

  def module_load

    add_setting :network, "ops"
    add_setting :channel, "auto-op"

    add_hook :ops, :pre_setting_set do |obj, setting, hash, translation|
      next unless obj.is_a? CCCB::Channel
      next unless setting == "auto-op"

      hash.keys.each do |nick|
        next if nick =~ /^[^!]+![^@]+@\S+$/
        user = obj.user_by_name(nick) or raise "Unable to find user with nick 'nick'"
        hash[user.from] = hash.delete(nick)
        translation[nick] = user.from
      end
    end

    add_hook :ops, :join do |message|
      auto_op = message.channel.get_setting("auto-op")
      if auto_op
        auto_op.each do |from,enabled|
          if enabled and message.from == from
            message.network.puts "MODE #{message.channel} +o #{message.nick}"
          end
        end
      end
    end

    add_hook :ops, :ctcp_OP do |message|
      next if message.to_channel?
      reply = message.user.register(message.ctcp_params.first)
      user_id = if message.user.delegated? 
        message.user.delegated.id
      else
        message.user.id
      end

      if message.user.authenticated?
        if message.network.get_setting("ops", user_id)
          message.user.channels.each do |channel|
            message.network.puts "MODE #{channel} +o #{message.nick}"
          end
          reply
        else
          "Sorry, you're not in the ops list"
        end
      else
        reply
      end
    end

    add_command :ops, "op me" do |message|
      next unless message.to_channel?
      user_id = if message.user.delegated? 
        message.user.delegated.id
      else
        message.user.id
      end
        
      if message.user.authenticated? and message.network.get_setting("ops", user_id)
        message.network.puts "MODE #{message.channel} +o #{message.nick}"
        message.reply "OK"
      else
        message.reply "Possibly if you registered"
      end
    end

    add_help(
      :ops,
      "ops",
      "Request #{@nick} ops you",
      [
        "There are two ways to get the bot to op you:",
        "First, you can send a CTCP OP command to the",
        "bot with your password. This will cause the",
        "bot to op you in every channel it can see you.",
        "The second method is to first send a CTCP ",
        "REGISTER command with your password. Following",
        "that, you can receive ops in any one channel",
        "by requesting the bot to 'op me'."
      ],
      :ops
    )


  end
end
