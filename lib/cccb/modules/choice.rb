require 'securerandom'

module CCCB::Core::Choice
  extend Module::Requirements

  needs :help
  
  def module_load
    add_request :choice, /^choose\s+(.*)\?/i do |match, message|
      choices = match[1].split( /(?:\s+(?:\s*(?:x?or(?=\W))\s*)+\s*|,)+\s*/ )
      if message.user.get_setting("options", "tease_me") and rand <= (get_setting("options", "tease_frequency")||0.1)
        "Whichever one makes you happy, okay?!"
      else
        choices[ SecureRandom.random_number( choices.length ) ]
      end
    end

    add_help(
      :choice,
      "choice",
      "Randomly choose one item from a set",
      [ 
        "Send the bot a request of the form:",
        "choose [ item1, [ item2, [...] ] ]?",
        "You can break the string of items up",
        "with 'or' or commas as you like, and",
        "there can be any number of items to ",
        "choose from."
      ]
    )

  end

end
