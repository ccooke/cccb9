
module CCCB::Core::Hugs
  extend Module::Requirements

  needs :bot

  def module_load
    add_setting :user, "hug", default: "/me feeds %(n) dark chocolate"
    
    #@doc
    # Hugging the bot ('/me hugs bot_name) will trigger a user-defined string to be printed.
    # The default is to feed the hugger with dark chocolate. You can set the string by using the setting command 'setting user::hug = string', with string being the whatever you want the bot to respond with. Include a %(n) in the string and it will be replaced with your current nick. Start with a /me for the bot to perform an action of its own.
    add_hook :hug, :ctcp_ACTION do |message|
      if message.ctcp_text =~ /^\s*hugs\s+#{ message.network.nick }\s*$/i
        string = message.user.get_setting( "hug" ).keyreplace do |key|
          case key
          when :%
            '%'
          when :n
            message.nick
          end
        end
        message.reply string
      end
    end

  end
end
