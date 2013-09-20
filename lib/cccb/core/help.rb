module CCCB::Core::Help
  extend Module::Requirements
 
  def add_help topic, summary, text, special = :none
    help.topics[ topic ] = {
      :summary => summary,
      :text => text,
      :special => special
    }
  end

  def module_load
    help.topics = {}

    add_setting :core, "help", :superuser, {}
    if have_feature? :httpserver
      set_setting("help", true, "via_web") unless get_setting("help", "via_web")
    end
    get_setting( "help" )["via_web"] = false

    add_request( /^loglevel (?<level>\w+)/i ) do |match, message|
      if message.user.superuser?
        level = match[:level].to_s.upcase.to_sym
        if self.class.constants.include? level
          logging.loglevel = self.class.const_get( level )
          "Okay, logging is now set to #{level}"
        else
          "No such log level #{level}"
        end
      else
        "Denied"
      end
    end

    add_request( /^h[ae]lp!?(?:\s+(?<topic>\w+))?$/i ) do |match, message|
      op = true
      superuser = true
      is_op = false
      is_superuser = false
      is_op = true if message.to_channel? and message.channeluser.is_op?
      is_superuser = true if message.user.superuser? 

      topic = match[:topic]
      cccb = CCCB.instance
      help = cccb.help

      if get_setting("help","via_web")
        "See #{cccb.get_setting("http_server","url")}/help/#{topic}"
      else
        if topic != 'fullindex' and help.topics.include? topic
          help = [ "Help for topic '#{topic}': " ] + help.topics[topic][:text].map { |l| ": #{l}" }
        else
          topics = help.topics.sort do |a,b| 
            aval, bval = [ a, b ].map do |t,v|
              case v[:special]
              when :info then 3
              when :none then 2
              when :ops then 1
              when :superuser then 0
              end
            end

            bval <=> aval
          end

          if topic == 'fullindex'
            starter = [ 
              "Help index (use 'help foo' to look up topic foo)"
            ]
          else
            topics = topics.select { |t,c| c[:special] == :none }
            starter = [
              "Simple index (use 'help foo' to look up topic foo),",
              "or 'help fullindex' for the complete index"
            ]
          end

          info = true
          help = starter + topics.map do |topic, content|
            case 
            when info && content[:special] == :none then
              info = false
              [ "Commands usable by anyone:" ]
            when op && content[:special] == :ops then 
              op = false
              [ "Commands only usable by channel ops:" ]
            when superuser && content[:special] == :superuser
              superuser = false
              [ "Commands only usable by bot admins:" ] 
            else
              []
            end + Array(content[:summary]).map do |line|
              s = "  %-15s%s" % [ topic, content[:summary] ]
              topic = ""
              s
            end
          end.flatten
        end
        if message.to_channel?
          message.network.msg message.nick, help
          "I've just opened a query with you."
        else
          help
        end
      end
    end

    add_help(
      "cccb8",
      "What is cccb8?",
      [ 
        "cccb8 is an IRC bot written in Ruby by ccooke.",
        "It is currently at version #{CCCB::VERSION}"
      ],
      :info
    )
    add_help(
      "requests",
      "Making requests of the bot",
      [
        "When making a request in a channel, always prefix",
        "the name of the bot - for instance: ",
        "<user> #{nick}: one or two?",
        "If you are in a query with the bot, you need no prefix."
      ],
      :info
    )

    add_help(
      "reload",
      "Reloading the bot",
      [
        "Sending the bot a CTCP RELOAD command causes it",
        "to halt all action, unload all files and plugins",
        "and reload itself entirely."
      ],
      :superuser
    )

    add_help(
      "puppet",
      "Special case commands",
      [ 
        "Sending the bot a CTCP PUPPET command followed by",
        "a valid IRC command will (if you are a superuser)",
        "cause the bot to send that command to the server"
      ],
      :superuser
    )

    CCCB::ContentServer.add_keyword_path('help') do |match|
      if match[:call] and help.topics.include? match[:call]
        {
          title: "Help topic: #{match[:call]}",
          blocks: [
            [ :content, 
              help.topics[match[:call].to_s][:text].map { |line|
                line = CGI::escapeHTML(line)
                line.split(/\s+/).map { |word|
                  if help.topics.include? word
                    "<a href=\"/help/#{word}\">#{word}</a>"
                  else
                    word
                  end
                }.join(" ")
              }.join("<br/>")
            ],
            [ :nav, "Return to <a href=\"/help\">index</a>" ],
          ]
        }
      else
        {
          title: "Index of help pages",
          template: :help_index,
          topics: help.topics
        }
      end
    end
  end
end
