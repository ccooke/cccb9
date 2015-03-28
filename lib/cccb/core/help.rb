module CCCB::Core::Help
  extend Module::Requirements
  needs :commands, :api_core

  def add_help(*args)
    info "Deprecated method add_help called at #{caller_locations(1,1)}"
  end
 
  def get_help(file,start)
    lines = File.read(file).lines
    help_markup = []
    seek = start - 2
    info "AT: #{lines[seek]}"
    while seek >= 0 and lines[seek].match(/^\s+#/)
      info "Add #{lines[seek]}"
      help_markup.unshift lines[seek].chomp
      seek -= 1
    end

    mode = :none
    base_info = { 
      doc: [], 
      detail: [],
      file: file,
      line: start,
      code: get_code(file,start)
    }
    help_markup[0..-1].each_with_object(base_info) do |line,h|
      line.gsub! /^\s*# ?/, ''
      info "HT: #{line}"
      if line.match /^\s*@(doc|detail|param)\z/
        if line.match /^\s*@doc/
          mode = :doc
        elsif match = line.match(/^\s*@detail(?:\s+(?<text>.*))?$/)
          mode = :detail
          h[:doc] << match[:text] if match[:text]
        elsif match = line.match(/^\s*@param\s+(?<param>\w+)\s+(?<type>\w+)\s+(?<help>.*?)\s*$/)
          h[:params] ||= {}
          h[:params][match[:param]] = {
            type: match[:type],
            text: match[:help]
          }
        else
          warning "Invalid help tag: #{line}"
        end
        next
      end

      case mode
      when :doc
        h[:doc] << line
        h[:detail] << line
      when :detail
        h[:detail] << line
      end
    end
  end

  def unindent(string)
    indent = string.each_line.inject(string.length) do |i,line|
      indent_length = string.length - string.lstrip.length
      i = if indent_length < i then indent_length else i end
    end
    string.each_line.map { |l| l[indent,-1] }.join
  end

  def hook_description_detail(hook, help_data = {})
    true
  end

  def hook_description(hook)
    unindent case hook
    when /^api\//
    when /^command\//
    else
      str = <<-EOF
        # Hook '#{hook}'
        Active hooks with this name:
      EOF
    end
  end

  def module_load
    help.topics = {}
    
    #@doc
    #@param hook The name of a hook in the bot
    #@param id (default: nil) 
    # Returns the help
    register_api_method :help, :doc do |**args|
      raise "Missing hook" unless args.include? :hook
      hook = args[:hook].to_sym
      if args.include? :id
        id = args[:id].to_i
        hook = hooks.db[hook].find.with_index { |h,i| i == id }
        help = get_help(hook[:source_file], hook[:source_line])
        hook_description_detail hook, help
      else
        hook_description hook 
      end
    end

    add_command :help, "help" do |message, (type, topic, number)|
      if topic 
        
      else
        #message.reply "See #{CCCB.instance.get_setting("http_server","url")}/network/#{message.network}/help/#{topic}"
        message.reply [ 
        ]
      end
    end

    add_help(
      :help,
      "cccb8",
      "What is cccb8?",
      [ 
        "cccb8 is an IRC bot written in Ruby by ccooke.",
        "It is currently at version #{CCCB::VERSION}"
      ],
      :info
    )

    add_help(
      :help,
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
      :help,
      "reload",
      "Reloading the bot",
      [
        "Sending the bot a CTCP RELOAD command causes it",
        "to halt all action, unload all files and plugins",
        "and reload itself entirely."
      ],
      :superuser
    )

    CCCB::ContentServer.add_keyword_path('help') do |session,match|
      features = session.network.get_setting("allowed_features").dup
      core_features = CCCB.instance.get_setting("allowed_features")
      core_features.each do |f,enabled|
        features[f] = enabled if enabled and not features.include? f
      end

      url = if session.network.name == "__httpserver__" then "/help/" else "/network/#{session.network.name}/help/" end
      local_topics = help.topics.each_with_object({}) do |(name,topic),hash| 
        detail2 "Topic: #{name} => #{topic}. My features: #{features}"
        hash[name] = topic if features.include? topic[:feature].to_s and features[topic[:feature].to_s]
      end

      if match[:call] and local_topics.include? match[:call]
        {
          title: "Help topic: #{match[:call]}",
          blocks: [
            [ :content, 
              local_topics[match[:call].to_s][:text].map { |line|
                line = CGI::escapeHTML(line)
                line.split(/\s+/).map { |word|
                  if local_topics.include? word
                    "<a href=\"#{url}#{word}\">#{word}</a>"
                  else
                    word
                  end
                }.join(" ")
              }.join("<br/>")
            ],
            [ :nav, "Return to <a href=\"#{url}\">index</a>" ],
          ]
        }
      else
        {
          title: "Index of help pages",
          template: :help_index,
          topics: local_topics
        }
      end
    end
  end
end
