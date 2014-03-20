module CCCB::Core::Yarn
  extend Module::Requirements
  needs :bot

  def module_load
    yarns = [
      "/me knits %n a fluffy scarf",
      "/me knits %n a nice new sweater",
      "/me knits %n a Jayne hat",
      "/me yarnbombs %n",
      "/me pounces the ball of yarn and chases it across channel",
      "/me pounces the ball of yarn and gets hopelessly tangled in it",
      "%n: if you want new socks, you can make them yourself!",
      "/me catches the ball of yarn and throws it back to %n",
      "/me chomps the yarn and thanks %n for the nom food",
      "roi7jh4b7sd6drod2rdepszzzppzzz965*cough* sorry, kitten bouncing after yarn on my keyboard"
    ]
    add_setting :network, "yarnballs", default: yarns
  
    add_hook :yarn, :message, filter: { ctcp: :ACTION } do |message|
      regex = /\syarn\s.*\s#{ message.network.nick }(?:[\s.]|$)/i

      next unless match = message.ctcp_text =~ regex

      reply = if m = message.user.get_setting("options", "yarn_action") and rand(5)<2
        m
      else
        yarnballses = message.network.get_setting("yarnballs")
        yarnballses.shuffle.first
      end

      reply.gsub!( /(?!:%)%n/, message.user.nick )
      reply.gsub!( /%%/, '%' )
      if reply.start_with?( "/me ") 
        reply.sub!( /^\/me\s+(.*)$/i, "\001ACTION \\1\001" )
      end
      message.reply reply
    end

    add_help(
      :yarn, 
      "yarn",
      "Throw a ball of yarn to make the bot go nuts",
      [ 
        "Throwing a ball of yarn at the bot ('/me throws a ball of yarn at #{@nick}') will trigger a random selection of responses",
        "from the bot, to which you can add a user-defined string to be printed. You can set the string by sending a CTCP YARN",
        "command to the bot with the argument being the string you want the bot to respond. Include a %n in the string and it will",
        "be replaced with your current nick. Start with a /me for the bot to perform an action of its own. This string will be",
        "added to the existing selection of responses, has a higher chance of cropping up, but won't always show up."
      ]
    )
  end
end

