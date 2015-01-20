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

  def get_code(file,line,banner = nil)
    lines = File.read(file).lines
    indent = lines[line - 1].index /[^[:space:]]/
    length = lines[line,lines.length].find_index { |l| l.index(/[^[:space:]]/) == indent }
    return [ '```' + (banner || "#{file}:#{line}") ] + lines[line-1,length+2].map(&:rstrip) + ['```']
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

    add_command :commands, "show commands" do |message, args|
      message.reply commands.registry.inspect
    end

    add_command :commands, "show features" do |message, args|
      message.reply hooks.features.keys.map(&:to_s).inspect
    end

    add_command :commands, "show hook" do |message, args|
      if args.count == 0
        message.reply hooks.db.keys.map(&:to_s).sort.join(", ")
      elsif args.count == 1
        id = 0
        message.reply hooks.db[args[0].to_sym].map { |h| "<Hook: #{args[0]} id: #{h[:id] = id += 1} Feature: #{h[:feature]} From: #{h[:source_file]}:#{h[:container]}:#{h[:source_line]}>" }
      else args.count == 2
        id = 0
        hook = hooks.db[args[0].to_sym].find do |h| 
          h[:id] ||= id += 1; 
          h[:id] == args[1].to_i
        end
        message.reply get_code(hook[:source_file],hook[:source_line])
      end
    end

    add_command :commands, "good bot" do |message, args|
      message.reply("Thank you")
    end

    servlet = Proc.new do |session, match|
      command = match[:call].split('/').join(' ')
      output_queue = Queue.new
      message = session.message
      message.instance_variable_set(:@content_server_strings, output_queue)
      message.instance_variable_set(:@http_match_object,match)

      verbose session.message.instance_variables
      def message.send_reply(final: false)
        unless @response.nil?
          data = @response.long_form
          @response = nil
          if @http_match_object[:keyword] == 'raw'
            @content_server_strings << "<pre>#{data}</pre>"
          else
            @content_server_strings << CCCB.instance.reply.web_parser.render(data)
          end
        end
        @content_server_strings << :EOM if final
      end
      
      process_command(message, command)
      text = output_queue.pop
      until (data = output_queue.pop) == :EOM
        text += data
      end

      {
        template: :html,
        text: text
      }
    end

    CCCB::ContentServer.add_keyword_path('command',&servlet)
    CCCB::ContentServer.add_keyword_path('raw',&servlet)

  end

end

