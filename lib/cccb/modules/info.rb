module CCCB::Core::InfoBot
  extend Module::Requirements
  needs :bot, :uri_detection, :api_core, :session

  def module_load
    add_setting :core, "info"
    add_setting :network, "info"
    add_setting :channel, "info"

    add_hook :info, :pre_setting_set do |obj, setting, hash|
      hash.each do |k,v|
        next unless v.respond_to? :gsub
        hash[k] = v.gsub(/\\n/, "\n")
      end
    end

    #@doc
    # Provides a simple information lookup system. 
    # 'info topic' will look up any information on the topic.
    # 'info topic = Some text' will set that topic for future lookups.
    # 'info' will return the list of things the bot knows (or a link to the web version of this list, if on IRC).
    add_command :info, "info" do |message, args|
      if args[0].nil? 
        args = [ "Index" ]
      end
      text = if args[1] == '='
        target = message.to_channel? ? :channel : :network
        user_setting message, "#{target}::info::#{args[0]}", args[2]
      elsif args[0] and value = message.get_setting("info", args[0])
        value
      elsif args[0] and value = CCCB.instance.get_setting("info", args[0])
        value
      elsif args[0]
        "No idea"
      else
        "#{CCCB.instance.get_setting("http_server","url")}/network/#{message.network}/info"
      end
      message.reply.fulltext = text
      message.reply.summary = text
    end

    add_keyword_expansion :i do |word|
      if word =~ /^[A-Z]\w+$/
        "[#{word}](/#{word})"
      elsif word.nil? or word == ""
        "[Index](/Index)"
      else
        "[#{word}](/command/info/#{word})"
      end
    end

    set_setting(
      "^/$ => /command/info/Index", 
      'http_server_rewrites', 'index'
    )
    set_setting(
      "^/(?<page>[A-Z]\\w+)$ => /command/info/{page}", 
      'http_server_rewrites', 'wiki'
    )

    pages = {
      login_success: "# Welcome\nYou are now logged in.",
      login_failure: "# Denied\nSorry, those credentials didn't match.",
    }

    set_setting pages[:login_success], "info", "LoginSuccess"
    set_setting pages[:login_failure], "info", "LoginFailure"

    #@doc
    #@param user The user name
    #@param password The password
    #@param network The network to log in to
    add_command :session, "login" do |message, args|
      if args.count == 0
        message.reply.fulltext = "<form method=\"POST\" action=\"/apiweb/session.login\">" + 
                                   "<ul>" +
                                     "<li>Username: <input type=\"text\" name=\"user\"></li>" +
                                     "<li>Password: <input type=\"password\" name=\"password\"></li>" +
                                     "<li><input type=\"submit\" value=\"Log In\"></li>" +
                                   "</ul>" +
                                   "<input type=\"hidden\" name=\"network\" value=\"lspace\">" +
                                 "</form>"
      else
        message.reply.fulltext = "I was sent: " + args.inspect
      end
      message.reply.summary = "Use the %(command:register) command to log in"
    end

    add_command :session, "logout" do |message, args|
      if message.user.authenticated?(message.network)
        message.set_setting(false, "session", "authenticated::#{message.network.name}")
      end
      message.reply "You have been logged out"
    end

    api_core.apiweb['session.login'] = Proc.new do |output, params, response|
      if output[:result]
        response.set_redirect(WEBrick::HTTPStatus::Found, "/LoginSuccess")
      else
        response.set_redirect(WEBrick::HTTPStatus::Found, "/LoginFailure")
      end
      { template: :html }
    end
  end
end
