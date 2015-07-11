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
    return "No help exists for that topic. Try the %(help:index)" unless help_for_type?( type, topic )
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
    hooks.db[hook].map.with_index do |h,i|
      next if index and index != i
      help = get_help(h[:source_file], h[:source_line])
      if count > 1 and index.nil?
        text << "### Summary for %(help:#{hook} #{i}) (from #{h[:source_file]}:#{h[:source_line]})"
        mode = :doc
      elsif index
        text << "### Synopsis for %(help:#{hook} #{i}) (from #{h[:source_file]}:#{h[:source_line]})"
        mode = :detail
      else
        text << "## Synopsis"
        mode = :detail
      end
      if help[mode].empty?
        text << "There is no documentation here yet"
      else
        text << help[mode]
      end
      if help[:params].count > 0 and (index or count == 1)
        text << "- - -"
        text << "| Argument | Type | Usage |"
        text << "| ----- | ----- | ----- |"
        help[:params].each do |pn,pm|
          text << "| #{pn} | #{pm[:type]} | #{pm[:text]} |"
        end
        text << "- - -"
      end
    end

    text
  end

  def help_expand(string, message = nil)
    string.keyreplace do |key|
      key = key.to_s
      case key 
      when /^list:(?<thing>\w+)/
        thing = $~[:thing]
        hooks.db.keys.select { |k| 
          k.to_s.start_with? "#{thing}/" 
        }.map { |c| 
          c.to_s.gsub(/^#{thing}\//,'').split('/').join(' ') 
        }.map { |c| 
        "[#{c}](/command/help/#{c})"
        }.each_slice(6).map { |l| l.join(" , ") }.join("\n")
      when /^help:(?<topic>.*)/
        "[help #{$~[:topic]}](/command/help/#{$~[:topic]})"
      when /^url:(?<command>[^:]+)(?::(?<args>.*))?$/
        args = $~[:args] || ""
        CCCB.instance.get_setting("http_server","url") + "/command/#{$~[:command]}/#{args}"
      when "help_url"
        '/command/help'  
      else
        "<<Unknown expansion: #{key.inspect}>>"
      end
    end
  end

  def add_help_topic(topic,*text)
    help.topics[topic.to_s] = text
  end

  def module_load
    help.topics = {}
    add_help_topic( 'index',
      "# Help Index #",
      "You can get help on several topics. Try:",
      "* [help commands](%(help_url)/commands) (for help on commands)",
      "* [help hooks](%(help_url)/hooks) (for help on hooks)",
      "* [help api](%(help_url)/api) (for help on api functions)",
    )

    help.types = [
      'command',
      'hook',
      'api'
    ]
    
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
      server = CCCB.instance.get_setting("http_server", "url")
      help_url="/command/help"
      full_url = help_url + "/" + args.join("/")
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

      reply = if type
        get_help_by_type(type, topic)
      elsif help.topics.include? string_topic
        help.topics[string_topic]
      else
        if type = ['command', 'hook', 'api' ].find { |t| help_for_type? t, topic }
          get_help_by_type(type, topic)
        else
          get_help_by_type(nil, topic)
        end
      end
      
      message.reply help_expand( Array(reply).join("\n"), message )
    end

  end
end
