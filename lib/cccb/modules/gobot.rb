module CCCB::Core::GoBot
  extend Module::Requirements

  def gobot_command(conversation, command)
    str = "#{command}\r\n"
    info "GOBOT >>> #{str}"
    info conversation.go
    conversation.go.puts str
    conversation.go.flush

    t = Time.now
    data = ""
    begin
      fragment = conversation.go.read_nonblock(4096)
      data += fragment
      sleep 0.1
    rescue Errno::EWOULDBLOCK => e
      if Time.now - t < 60 and fragment != "\n\n"
        retry
      end
    end
    info "GOBOT <<< #{data}"
    data
  end

  def module_load
    #@doc
    # Begins a new Conversation, in which a game of Go is played
    # Commands recognised are "showboard", "resign", "pass", and a move location
    # Very much a work in progress.
    add_command :gobot, %w{ play go } do |message, args|
      conversation = api('conversation.new', 
        __message: message,
      )
      conversation.hook_name = :gobot_conversation

      info "go args : #{args}"
      conversation.go = IO.popen(%w{ gnugo --mode gtp}, mode: 'w+')
      conversation.side = args[0] || 'black'
      conversation.cpu_side = conversation.side == 'black' ? 'white' : 'black'
      conversation.size = args[1].to_i || 9
      conversation.handicap = args[2].to_i || 0

      gobot_command conversation, "boardsize #{conversation.size}"
      gobot_command conversation, "fixed_handicap #{conversation.handicap}" unless conversation.handicap == 0
      gobot_command conversation, "genmove #{conversation.cpu_side}" if conversation.side == 'black'
      conversation.reply gobot_command(conversation,"showboard")
    end

    add_hook :gobot, :gobot_conversation do |conversation, text|
      case text
      when /^end$/i
        command = "final_score"
      when /^resign$/i
        conversation.reply "#{conversation.cpu_side[0].upcase}+res"
        conversation.end
      when /^\p{Letter}\p{Digit}+$/, /^pass$/i
        reply = gobot_command(conversation, "play #{conversation.side} #{text}").chomp
        if reply == "= \n"
          command = "genmove #{conversation.cpu_side}"
        else
          conversation.reply reply.split(/\n/)
        end
      else
        command = text
      end
      conversation.reply gobot_command(conversation, command).split(/\n/) if command
    end

    add_hook :gobot, :gobot_conversation__cleanup do |conversation|
      conversation.go.puts("quit\n")
      conversation.go.close
    end

  end
end
