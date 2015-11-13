module CCCB::Core::Commands
  extend Module::Requirements

  needs :bot, :filter_hooks

  COMMAND_WORD_REGEX = /
    (?:
      (?<quote> ["'] )
      (?<quoted_arg> 
        (?<escape> \\ ){0}
        (?<escaped_char> \g<escape>. ){0}
        (?:
          \g<escaped_char>
          |
          (?!\g<quote>).
        )*?
      )
      \g<quote>
    |
      (?<command_arg> \S+)
    )
  /x

  def get_code(file,line)
    if $load_file_cache.include? file
      lines = $load_file_cache[file].lines
    else
      lines = File.read(file).lines
    end
    indent = lines[line - 1].index /[^[:space:]]/
    length = lines[line,lines.length].find_index { |l| l.index(/[^[:space:]]/) == indent }
    lines[line-1,length+2].map(&:rstrip)
  end

  def expand_words(list)
    list = Array(list)
    arrays,non_arrays = list.partition { |i| i.respond_to? :each }
    if arrays.empty?
      [ non_arrays.join(' ') ]
    else
      first_array,*arrays = arrays
      products = first_array.product(*arrays)
      products.each_with_object([]) { |i,expand_wordsinations| 
        expand_wordsinations << list.map { |j| 
          j.respond_to?(:each) ? i.shift : j } 
        }.map { |i| i.join(' ') 
      }
    end
  end

  def add_command(feature, hook_names, &block)
    debug "WORDS: #{expand_words(hook_names)}"
    expand_words(hook_names).each do |hook_name|
      real_hook_name = (["command"] + (hook_name.to_s.split)).join('/').to_sym
      debug "Adding command #{real_hook_name}"
      cursor = commands.registry
      real_hook_name.to_s.split(%r{/}).each do |w|
        cursor[:words][w] ||= { words: {}, hooks: [] }
        cursor = cursor[:words][w]
        cursor[:hooks] += [ real_hook_name ]
      end
      cursor[:hook] = real_hook_name
      commands.feature_lookup[real_hook_name] = feature
      add_hook feature, real_hook_name, generator: 3, &block
    end
  end

  def auth_command(auth_class, message)
    reason = case auth_class 
    when :any
      return true
    when :channel
      return true if message.to_channel? and message.channeluser.is_op?
      "You are not a channel op"
    when :network
      return true if message.network.get_setting("trusted").include? message.from
      "You are not on the network trusted list"
    else
      # unset of superuser
      return true if message.user.superuser?
      "You are not a superuser"
    end
    message.reply.title = "Access denied for #{message.reply.title}"
    message.reply.summary = "Denied: #{reason}"
    message.reply.fulltext = "Access denied for authorisation class '#{auth_class}': #{reason}"
    raise "Denied: #{reason}"
  end

  def process_command(message,command)
    string = command
    spam "In words, parsing #{string}"
    words = string.scan(COMMAND_WORD_REGEX).map do |(_, quoted_word, _, _, simple_word)|
      simple_word.nil? ? quoted_word : simple_word
    end
    words.unshift("command")
    spam "Looking for command #{words.inspect}"
    cursor = commands.registry
    args = words.map &:dup
    pre = []
    hook = :empty_command
    words.each do |word|
      schedule_hook :debug_command_selection, words, cursor[:words].keys
      spam "CURSOR: #{cursor} WORD: #{word}"
      if cursor[:words].include? word
        pre << args.shift
        cursor = cursor[:words][word]
        hook = cursor[:hook] || hook
        spam "Command word #{word}, hook #{hook}"
      else
        break
      end
    end
    rate_limit_by_feature( message, commands.feature_lookup[hook], hook )
    if hook_runnable? hook, message, *args
      verbose "Scheduling hook for command: #{hook}->(#{args.inspect}) #{hook_runnable?(hook,*args).inspect}"
      schedule_hook hook, message, args, pre, cursor, hook, run_hook_in_thread: true do
       # message.reply "In post block"
       # message.reply "Response: #{message.instance_variable_get(:@response)}"
       # message.reply "Data: #{message.reply.minimal_form}"
        message.send_reply final: true
      end
    else
      message.reply "Command disabled"
      message.send_reply final: true
    end
  end

  def module_load
    default_setting true, "allowed_features", "commands"

    commands.registry = {
      words: {}
    }
    commands.feature_lookup = {}

    add_hook :core, :exception, top: true do |e, hook, item, (message,*args)|
      next unless hook =~ /^command\//
      message.reply.title = "Error"
      message.reply.summary = "Error: #{e.message}"
      :end_hook_run
    end

    #@detail
    # Detects command requests and processes them
    add_request :core, /^(.*)$/ do |match, message|
      process_command(message, match[1])
      nil
    end

    add_hook :core, :empty_command do |message, args, pre, cursor|
      pre.shift
      #next unless pre.count > 0
      enabled = cursor[:words].select { |k,v| 
        v[:hooks].any? { |h| 
          hook_runnable? h, message
        } 
      }.map(&:first).join(", ")
      #message.reply "Ambiguous command '#{pre.join " "}'. Possible commands from this base: #{enabled}"
    end

    #@doc
    # List the active commands. Note: This can be a long list!
    add_command :commands, "show commands" do |message, args|
      message.reply commands.registry.inspect
    end

    #@doc
    # Lists the currently loaded features. 
    # Every command and api call is associated with a feature, and features can be enabled or disabled at the channel, network or global level.
    add_command :commands, "show features" do |message, args|
      message.reply hooks.features.keys.map(&:to_s).inspect
    end

    #@doc
    # Lists all hooks the bot currently knows
    # This contains all commands, api calls and internal features - it is a *long* list.
    add_command :commands, "show hook" do |message, args|
      if args.count == 0
        list = hooks.db.keys.map(&:to_s).sort.map { |h|
          "1. [`#{h}`](/command/show hook/#{h})"
        }.join("\n")
        message.reply.fulltext = "# Currently loaded hooks: \n#{list}"
        message.reply.summary = "This is too long a list for IRC. Try looking at #{CCCB.instance.get_setting("http_server","url") + "/command/show hook"}"
      elsif args.count == 1
        list = hooks.db[args[0].to_sym].map.with_index do |h,i| 
          "1. [`show hook #{args[0]} #{i}`](/command/show hook/#{args[0]} #{i})  \n" +
          "Feature: `#{h[:feature]}` From: `#{h[:source_file]}:#{h[:container]}:#{h[:source_line]}`"
        end
        if list.empty?
          message.reply.summary = "There are no hooks attached to the `#{args[0]}` event at present"
        else
          message.reply.summary = "# hooks attached to the `#{args[0]}` event.\n" + list.join("\n")
        end
        message.reply.fulltext = message.reply.summary + "\n\n- - -\n[Hook list](/command/show hook)"
      else args.count == 2
        hook = hooks.db[args[0].to_sym].find do |h| 
          h[:id] == args[1].to_i
        end
        source = [
          *get_help(hook[:source_file],hook[:source_line])[:raw],
          *get_code(hook[:source_file],hook[:source_line])
        ].map { |l| l.gsub(/^/, '    ') }

        full = [
          "# Source for hook `#{args[0]}` (from `#{hook[:source_file]}:#{hook[:source_line]}`)", 
          *source
        ]
        message.reply.fulltext = full.join("\n")

        if source.count > 6
          message.reply.summary = "This is too long for IRC. Try looking at #{CCCB.instance.get_setting("http_server","url") + "/command/show hook/#{args.join(" ")}"}"
        end
      end
    end

    info "Minimal form for #{self.inspect}"
    #@doc
    # Tells the bot it is good. What, you expected more?
    # ... The bot will say "Thank you". Does that help?
    add_command :commands, "good bot" do |message, args|
      message.reply("Thank you")
    end

    servlet = Proc.new do |session, match, req, res|
      split = match[:call].partition('/')
      command = URI.unescape(split[0] + " " + split[2])

      message = session.message
      message.renderer = CCCB.instance.web_parser
      message.output_form = :long_form
      if match[:keyword] == 'raw'
        message.return_markdown = true 
        template = :raw
      else
        template = :default
      end

      output_queue = Queue.new
      message.write_func = ->(l,m){ output_queue << l }
      message.write_final_func = ->{ output_queue << :EOM }

      process_command(message, command)
      text = output_queue.pop
      until (data = output_queue.pop) == :EOM
        text += data
      end

      {
        header_items: [],
        session: session,
        template: template,
        title: message.reply.title,
        blocks: [
          [ "command.#{split[0].split(" ").join(".")}",
            text
          ]
        ]
      }
    end

    CCCB::ContentServer.add_keyword_path('command',&servlet)
    CCCB::ContentServer.add_keyword_path('raw',&servlet)

  end

end

