module CCCB::Core::Ops
  extend Module::Requirements

  needs :session

  def module_load

    add_setting :network, "ops"

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

    add_request :ops, /^op me$/ do |match, message|
      next unless message.to_channel?
      user_id = if message.user.delegated? 
        message.user.delegated.id
      else
        message.user.id
      end
        
      if message.user.authenticated? and message.network.get_setting("ops", user_id)
        message.network.puts "MODE #{message.channel} +o #{message.nick}"
        "OK"
      else
        "Possibly if you registered"
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
