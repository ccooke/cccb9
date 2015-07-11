require 'securerandom'

module CCCB::Core::Choice
  extend Module::Requirements

  needs :help
  
  def module_load
    #@doc
    # Ask the bot to choose something for you. The question is split on commas or 'or' and must end in a '?'
    # e.g.: "!choose this or that?", "!choose work, procrastinate, kill zombies?"
    add_command :choice, "choose" do |message, args|
      choices = args.join(' ').split( /(?:\s+(?:\s*(?:x?or(?=\W))\s*)+\s*|,)+\s*/ )

      if message.user.get_setting("options", "tease_me")
        frequency = message.user.get_setting("options","tease_frequency") || 0.1
        if rand <= frequency.to_f
          message.reply "Whichever one makes you happy, okay?!"
          next
        end
      end
        
      message.reply( choices[ SecureRandom.random_number( choices.length ) ] )
    end

  end

end
