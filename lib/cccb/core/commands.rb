module CCCB::Core::Commands
  extend Module::Requirements

  needs :bot

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

  def add_command(feature, hook_name, &block)
    hook_name = (["command"] + (hook_name.to_s.split)).join('/').to_sym
    debug "Adding command #{hook_name}"
    cursor = commands.registry
    hook_name.to_s.split(%r{/}).each do |w|
      cursor[:words][w] ||= { words: {} }
      cursor = cursor[:words][w]
    end
    cursor[:hook] = hook_name
    add_hook feature, hook_name, &block
  end

  def module_load
    commands.registry = {
      words: {}
    }

    add_request :commands, /^(.*)$/ do |match, message|
      string = match[1]
      verbose "In words, parsing #{string}"
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
      debug "Scheduling hook for command: #{hook}->(#{args.inspect})"
      schedule_hook hook, message, args, pre, cursor
      nil
    end

    add_hook :commands, :empty_command do |message, args, pre, cursor|
      pre.shift
      next unless pre.count > 0
      message.reply "Ambiguous command '#{pre.join " "}'. Possible commands from this base: #{cursor[:words].keys.join(", ")}"
    end

    add_command :commands, "show commands" do |message, args|
      message.reply commands.registry.inspect
    end

    add_command :commands, "show hook" do |message, args|
      if args.count == 0
        message.reply hooks.db.keys.map(&:to_s).inspect
      else
        message.reply hooks.db[args[0].to_sym]
      end
    end
  end


end
