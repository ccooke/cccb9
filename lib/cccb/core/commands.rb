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

  def get_code(file,line,banner = nil)
    lines = File.read(file).lines
    indent = lines[line - 1].index /[^[:space:]]/
    length = lines[line,lines.length].find_index { |l| l.index(/[^[:space:]]/) == indent }
    return [ "  " * indent + "# #{banner || "From #{file}:#{line}"}" ] + lines[line-1,length+2]
  end

  def add_command(feature, hook_name, &block)
    hook_name = (["command"] + (hook_name.to_s.split)).join('/').to_sym
    debug "Adding command #{hook_name}"
    cursor = commands.registry
    hook_name.to_s.split(%r{/}).each do |w|
      cursor[:words][w] ||= { words: {} }
      cursor = cursor[:words][w]
    end
    cursor[:hook] = hook_name
    add_hook feature, hook_name, generator: true, &block
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
    raise "Denied: #{reason}"
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
  end


end
