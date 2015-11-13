module CCCB::Core::Help
  extend Module::Requirements
  needs :commands, :api_core

  def add_help(*args)
    info "Deprecated method add_help called at #{caller_locations(1,1)}"
  end
 
  def get_help(file,start)
    info "Help for #{file}, #{start}"
    if $load_file_cache.include? file
      lines = $load_file_cache[file].lines
    else
      lines = File.read(file).lines
    end
    help_markup = []
    seek = start - 2
    while seek >= 0 and lines[seek].match(/^\s+#/)
      help_markup.unshift lines[seek].chomp
      seek -= 1
    end

    mode = :none
    base_info = { 
      raw: [],
      doc: [], 
      params: {},
      detail: [],
      file: file,
      line: start,
      code: get_code(file,start)
    }
    help_markup[0..-1].each_with_object(base_info) do |line,h|
      h[:raw] << line
      line = line.gsub /^\s*# ?/, ''
      if line.match /^\s*@(doc|detail|param)(?:\s.*|)$/
        if line.match /^\s*@doc/
          mode = :doc
        elsif match = line.match(/^\s*@detail(?:\s+(?<text>.*))?$/)
          mode = :detail
          h[:doc] << match[:text] if match[:text]
        elsif match = line.match(/^\s*@param\s+(?<param>\w+)\s+(?<type>\w+)\s+(?<help>.*?)\s*$/)
          h[:params][match[:param]] = {
            type: match[:type],
            text: match[:help]
          }
        else
          warning "Invalid help tag: #{line}"
        end
        next
      end

      line = line + "  " unless line =~ /^\s*$/

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
      indent_length = line.length - line.lstrip.length
      i = if indent_length < i then indent_length else i end
    end
    string.each_line.map { |l| l[indent,-1] }.join
  end

  def hook_description_detail(hook, help_data = {})
    true
  end

  def get_hook_by_type(type, topic)
    case type
    when 'command'
      "command/#{topic.join("/")}".to_sym
    when 'hook'
      topic.first.to_sym
    when 'api'
      "api/#{topic.first}".to_sym
    else 
      nil
    end
  end

  def get_help_by_type(type, topic)
    unless help_for_type?( type, topic )
      s = ["No help exists for that topic. Try the %(help:index)"]
      return s, s
    end
    args = {
      hook: get_hook_by_type(type, topic)
    }
    if topic.first =~ /^\d+$/
      args[:id] = topic.first.to_i
    end

    api :"core.help", **args
  end

  def help_for_type?(type, topic)
    hook_name = get_hook_by_type(type, topic)
    debug("Looking up help for #{hook_name.inspect}")
    hooks.db.include? hook_name
  end

  def hook_description(hook, index = nil)
    hook_str = hook.to_s
    text = case hook_str
    when /^api\//
      hook_str = hook_str.gsub(/^api\//, "")
      [
        "# API call '#{hook_str}'"
      ]
    when /^command\//
      hook_str = hook_str.gsub(/^command\//,"").split("/").join(" ")
      [
        "# Command '#{hook_str}'"
      ]
    else
      [
        "# Hook '#{hook}'",
      ]
    end 

    count = hooks.db[hook].count
    if count > 1 and index.nil?
      text << "*This hook has #{count} implementations*"
      text << "Each will run in turn"
    end

    help_text = { 
      doc: [],
      detail: []
    }

    hooks.db[hook].map.with_index do |h,i|
      next if index and index != i
      help = get_help(h[:source_file], h[:source_line])
      if count > 1 and index.nil?
        text << "### Summary for %(help:#{hook} #{i}) (from #{h[:source_file]}:#{h[:source_line]})"
      elsif index
        text << "### Synopsis for %(help:#{hook} #{i}) (from #{h[:source_file]}:#{h[:source_line]})"
      else
        text << "## Synopsis"
      end

      help_text.keys.each do |mode|
        tmp = text.dup
        if help[mode].empty?
          tmp << "There is no documentation here yet"
        else
          tmp << help[mode]
        end
        if help[:params].count > 0 and (index or count == 1)
          tmp << ""
          tmp << "| Argument | Type | Usage |"
          tmp << "| ----- | ----- | ----- |"
          help[:params].each do |pn,pm|
            tmp << "| #{pn} | #{pm[:type]} | #{pm[:text]} |"
          end
          tmp << ""
        end
        help_text[mode] << tmp
      end
    end
    
    return help_text[:detail], help_text[:doc]
  end

  def get_hooks_by_prefix(thing)
    hooks.db.keys.select { |k| 
      k.to_s.start_with? "#{thing}" 
    }
  end

  def get_hooks_by_feature(prefix = nil, sort: false, cut_prefix: false)
    list = get_hooks_by_prefix(prefix).map.with_object({}) do |c,h|
      hooks.db[c.to_sym].each do |hook|
        h[hook[:feature]] ||= []
        name = if cut_prefix
          hook[:hook].to_s.gsub(/^#{prefix}\//, "")
        else
          hook[:hook]
        end
        h[hook[:feature]] << { name: name, id: hook[:id], hook: hook[:hook] }
      end
    end
    if sort
      list.sort_by { |k,v| k }
    else
      list
    end
  end

  def run_inline_command(message, command, param, raw: false)
    submessage = CCCB::Message.new(
      message.network,
      ":#{message.from} PRIVMSG #{message.network.nick} :#{command} #{param}"
    )
    submessage.output_form = message.output_form
    submessage.renderer = message.renderer
    submessage.return_markdown = raw
    queue = Queue.new
    submessage.write_func = ->(l,m){ queue << l }
    submessage.write_final_func = ->{ queue << :EOM }

    process_command(submessage, "#{command} #{param}")
    text = queue.pop
    until (data = queue.pop) == :EOM
      text += data
    end

    text
  end

  def add_help_topic(topic_name,*text)
    topic = {
      doc: [],
      detail: [],
      description: 'This topic has no description'
    }
    next_mode = 'doc'
    indent = nil
    text.join("\n").each_line do |line|
      indent ||= line.index(/\S/)
      line[0...indent] = ""

      mode = next_mode
      line.chomp!
      case line
      when /^\s*@(?<mode>doconly|doc|detail)(?:\s+(?<text>.*?)\s*)?$/
        if $~[:text]
          mode = $~[:mode]
          line = $~[:text]
        else
          next_mode = $1
          next
        end
      when /^\s*@description\s+(.*?)\s*$/
        topic[:description] = $1
        next
      end

      topic[:detail] << line unless mode == 'doconly'
      topic[:doc] << line unless mode == 'detail'
    end

    help.topics[topic_name] = topic
  end

  def module_load
    help.topics = {}
    add_help_topic( 'index',
      "@description This index",
      "%(help_topic_list)",
    )
    add_help_topic( 'commands', 
      "@description Commands available to the bot",
      "# Commands #",
      "The following commands are known to the bot, grouped by the bot feature that needs to be enabled to use them: ",
      "@doconly %(compact_hooks_by_feature:command)",
      "@detail %(hooks_by_feature:command)",
    )
    add_help_topic( 'hooks', 
      "@description All hooks known to the bot",
      "# Hooks #",
      "Hooks are named events that code can trigger upon. Everything in the bot is done with these events - from timers to server messages to bot commands. The list of hooks in the bot is very long, since there are hooks for every bot command, for every API call and for every internal event that the bot generates. You can get a list of the hooks with the [show hook](/command/show hook) command, but the list will only be generated in full on the web.",
      "@doconly %(compact_hooks_by_feature)",
      "@detail %(hooks_by_feature)"
    )
    add_help_topic( 'api',
      "# API #",
      "@description API hooks supported by the bot",
      "The api consists of some calls in the bot that have been packaged up for internal and external calls. The interface is solid, but there aren't a huge number of these as yet.",
      "The list of current API calls is:",
      "@doconly %(compact_hooks_by_feature:api)",
      "@detail %(hooks_by_feature:api)",
      "You can call an API method by making a HTTPS request to %(url:api/method.name), passing arguments in the query string."
    )

    add_keyword_expansion :help_topic_list do 
      [
        "",
        "| Help Topic | Description |",
        "|---|:--|",
        *help.topics.sort_by { |k,m| k }.reject { |(k,m)| k == 'index' }.map { |(k,m)|
          "| %(help:#{k}) | #{m[:description]} |"
        }
      ].join("\n")
    end

    add_keyword_expansion :compact_hooks_by_feature do |prefix|
      get_hooks_by_feature(prefix, cut_prefix: true, sort: true).map { |(k,hs)|
        str = "## Feature: `#{k}`\n"
        hooks = hs.sort_by { |h| h[:hook] }.map { |h|
          "_`#{h[:name].to_s.split('/').join(' ')}`_"
        }
        width = hooks.max_by { |h| h.length }.length + 1
        columns = 80 / width
        str + hooks.each_slice(columns).with_object([]) { |hs,a|
          a << hs.map { |h| 
            Kernel.sprintf("%-#{width}s",h) 
          }.join
        }.join("\n")
      }.join("\n\n")
    end

    add_keyword_expansion :hooks_by_feature do |prefix|
      get_hooks_by_feature(prefix, cut_prefix: true, sort: true).map { |(k,hs)|
        str = "## Feature: `#{k}`\n"
        str + hs.sort_by { |h| h[:hook] }.map { |h|
          "1. [help](/command/help/#{h[:name]}) [code](/command/show hook/#{h[:hook]} #{h[:id]}) `#{h[:name]}`"
        }.join("\n")
      }.join("\n\n")
    end

    add_keyword_expansion :help do |topic|
      "[`#{topic || 'Help'}`](/command/help/#{topic})"
    end

    add_keyword_expansion :command do |args|
      if match = args.match(/(?<command>[^:]+)(?::(?<args>.*))?$/)
        args = $~[:args] || ""
        cmd = [ $~[:command], $~[:args] ].join(" ")
        "[`#{cmd}`](/command/#{$~[:command]}/#{URI.escape(args,"#?=")})"
      end
    end

    add_keyword_expansion :url do |args|
      if match = args.match(/(?<command>[^:]+)(?::(?<args>.*))?$/)
        args = $~[:args] || ""
        CCCB.instance.get_setting("http_server","url") + "/#{$~[:command]}/#{args}"
      end
    end

    add_keyword_expansion :inline_command do |args, message|
      command, _, param = args.partition(':')
      run_inline_command(message, command, param, raw: true)
    end

    add_keyword_expansion :inline_command_link do |args, message|
      command, _, param = args.partition(':')
      "%(command:#{command}:#{param})\n#{run_inline_command(message, command, param, raw: true)}"
    end

    help.types = [
      'command',
      'hook',
      'api'
    ]

    default_setting(10,'options', 'irc_help_max_length')
    default_setting(false, 'options', 'irc_help_reply_in_query')
    default_setting(false, 'options', 'irc_help_full_text')
    
    #@doc
    #@param hook string The name of a hook in the bot
    #@param id integer (default: nil) An index into the hook list
    # Returns the help
    register_api_method :core, :help do |**args|
      raise "Missing hook" unless args.include? :hook
      hook = args[:hook].to_sym
      if args.include? :id
        id = args[:id].to_i
        hook = hooks.db[hook].find.with_index { |h,i| i == id }
        help = get_help(hook[:source_file], hook[:source_line])
        hook_description_detail hook, help
      else
        hook_description hook, id
      end
    end

    #@doc
    #@param type string A category to look for the topic in. Choices include 'command', 'hook' and 'api'
    #@param topic string A topic to look for help on.
    # Usage: help [topic] | [type [topic]]
    # Displays help on various topics 
    add_command :help, "help" do |message, args|
      if args.count == 0
        topic = ['index']
      elsif args.count == 1
        topic = args
      elsif args.count == 2 and help.types.include? args.first
        type, *topic = args
      else
        topic = args
      end
      string_topic = topic.join(" ")

      full, summary = if type
        get_help_by_type(type, topic)
      elsif help.topics.include? string_topic
        [ help.topics[string_topic][:detail], help.topics[string_topic][:doc] ]
      else
        if type = ['command', 'hook', 'api' ].find { |t| help_for_type? t, topic }
          get_help_by_type(type, topic)
        else
          get_help_by_type(nil, topic)
        end
      end

      if message.replyto.get_setting("options", "irc_help_reply_in_query") and message.to_channel?
        message.reply "#{message.user.nick}: Okay, I've replied in a query"
        message.replyto = message.user
      end

      message.reply.fulltext = full.join("\n")
      message.reply.summary = summary.join("\n")

      max_length = message.replyto.get_setting("options", "irc_help_max_length").to_i
      if message.reply.summary.length < message.reply.fulltext.length 
        message.reply.summary += "\n*This text has been abbreviated*. The full version is at %(url:command/help:#{args.join(" ")})."
        max_length += 1
      end

      if message.replyto.get_setting("options", "irc_help_full_text")
        message.output_form = :long_form
      end

      message.send_reply do |text, renderer, output_form|
        next text unless output_form == :minimal_form
        if text.count > max_length
          text[0...max_length] + renderer.render(
              CCCB.instance.keyword_expand(
                "*Cut for length* See %(url:command/help:#{args.join(" ")}) for the full version",
              message
            )
          ).lines
        else
          text
        end
      end
    end

  end
end
