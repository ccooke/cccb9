require 'securerandom'

class CCCB::DieRoller

  DICE_REGEX = /
    \s*
    (?:
      ([-+])?
      (\d+)
    )?
    (?:
      d
      (\d+|F)
    )?
    (!?)
    (d(?:\d*)[hl]|r(\d+)(?:,(\d+)?)?)?
    \s*
  /ix

  def initialize(message)
    @message = message
    if @message.to_channel?
      @roll_style = @message.channel.get_setting( "options", "dice_rolls_compact" ) ? :compact : :full
    else
      @roll_style = :full
    end
    @dice_current_jinx = if message.user.persist[:dice_jinx]
      :pending_jinx
    else
      :no_jinx
    end
  end

  def dice_colour( max, rolls )
    string = rolls.each_with_object("") do |roll,str| 
      #p roll, str
      if roll == 1
        str << "\x03" + "041" + "\x0F,"
      elsif roll > max
        str << "\x03" + "03#{roll}" + "\x0F!,"
      elsif roll == max
        str << "\x03" + "11#{roll}" + "\x0F,"
      else
        str << "#{roll},"
      end

    end
    #string.force_encoding("US-ASCII")
    #p string
    string.gsub!( /,$/, '' )
    string
  end

  def roll_die( die, explode = false )
    debug "Jinx pending" if @dice_current_jinx != :no_jinx
    roll = 0
    loop do
      r = if @dice_current_jinx != :no_jinx and SecureRandom.random_number( 2 ) == 0
        debug "Jinxed"
        @dice_current_jinx = :applied_jinx
        SecureRandom.random_number( die.to_i / 2 ) + 1
      else
        SecureRandom.random_number( die.to_i ) + 1
      end
      roll += r
      redo if explode and r == die.to_i
      break
    end
    roll
  end

  def apply_dice_modifier(mod,die,rolls,output)
    if mod =~ /^d(\d+)?(h|l)$/
      count = $1 ? $1.to_i : 1
      count = count >= rolls.count ? rolls.count - 1 : count
      drop = []
      count.downto(1).each do
        outlier = $2 == 'h' ? rolls.max : rolls.min
        rolls.delete_at( rolls.index( outlier ) )
        drop << outlier
      end
      output << "(drop #{dice_colour(die.to_i, drop)})"
    elsif mod =~ /^r\d/
      reroll ||= 1
      reroll = reroll.to_i > die.to_i ? 0 : reroll
      reroll_count ||= 1
      reroll_count = reroll_count.to_i > 10 ? 10 : reroll_count
      rerolls = []
      rolls = rolls.map do |r|
        debug "Roll: #{r}"
        if r <= reroll.to_i
          debug "Reroll!"
          old_roll = r
          limit = reroll_count.to_i
          while r <= reroll.to_i and (limit -= 1) >= 0 
            debug "#{limit} rerolls left"
            old_r = r
            r = roll_die(die, explode) 
            debug "new roll: #{r}"
            rerolls << [ old_r, r ]
          end
          r
        else
          r
        end
      end
      unless rerolls.empty?
        output << "(rerolls: " + rerolls.map { |(old,new)| "#{old}->#{new}" }.join(", ") + ")"
      end
      #p rolls
    end
    return rolls,output
  end

  def dice_string( string, default = "+1d20" )
    #p string, default
    total = 0
    output = []
    string.gsub! /\s*/, ''
    string = "+#{string}" unless string.match /^[-+]/
    unless string.match( /(?:#{DICE_REGEX})+/ )
      return 0, [ "That wasn't (entirely?) a dice expression. I support expressions like '2d6 +3', '4d6 dl' or '+5' (I'll assume d20+5 for the last one)" ]
    end
    scanned = string.scan( DICE_REGEX )
    debug scanned.inspect
    scanned.each do |(sign,count,die,explode,mod,reroll,reroll_count)|
      next unless count or die
      explode = ( explode == "!" )
      spam [ sign, count, die, mod ].inspect
      sign ||= '+'
      if die.nil? and output.empty?
        (total, output) = dice_string( default )
      end

      fudge_die = false
      unless die.nil?
        if die =~ /f/i
          die = 6
          fudge_die = true
        end
        return 0, [ "Sorry, no count over 200" ] if count.to_i > 200
        return 0, [ "Sorry, no die over 1,000,000" ] if die.to_i > 1000000
        count ||= 1
        rolls = nil
        value = 0
        if fudge_die
          rolls = [ (1..count.to_i).map { roll_die( die, false ) }.map { |r| 
            if r <= 1 * die.to_i / 3
              total -= 1
              "-"
            elsif r <= 2 * die.to_i / 3
              " "
            else
              total += 1 
              "+"
            end
          } ]
          output << "#{sign}#{count}dF(#{rolls.join})"
          value = rolls.join
          total = sprintf("%+d", total)
        else
          rolls = (1..count.to_i).map { roll_die( die, explode ) }
          output << "#{sign}#{count}d#{die}(#{dice_colour(die.to_i,rolls)})"
          (rolls,output) = apply_dice_modifier(mod,die,rolls,output)
          value = rolls.inject(:+)
          total = total.send( sign.to_sym, value )
        end
      else
        count ||= 0
        total = total.send( sign.to_sym, count.to_i )
        output << "#{sign}#{count}"
      end
    end
    return total, output
  end

  def message_die_roll(nick, rolls, mode )
    compact = ( (mode != 'roll') || (@roll_style == :compact) )
    batch = []
    rolls.each do |entry|
      #p "EN:", entry, mode, compact
      if compact and entry[:type] != :roll and not batch.empty?
        @message.network.msg @message.replyto, "==> #{batch.inspect}"
        batch = []
      end

      case entry[:type]
      when :roll 
        if mode == 'dmroll'
          if nick.downcase == @message.user.id
            @message.network.msg @message.user.nick, "#{entry[:detail].join} ==> #{entry[:roll]}"
          end
          
          dm = @message.channel.get_setting("options", "dm")

          if @message.to_channel? and dm and dm.downcase == @message.user.id
            @message.network.msg dm, "#{m.nick} rolled: #{entry[:detail].join} ==> #{entry[:roll]}"
          end
        end
        if compact
          batch << entry[:roll]
          next
        end
        @message.network.msg @message.replyto, if mode == 'roll'
          "#{entry[:detail].join} ==> #{entry[:roll]}"
        end
      when :pointbuy
        @message.network.msg @message.replyto, "Point-buy equivalent: D&D #{entry[:dnd]}, Pathfinder #{entry[:pf]}"
      when :reroll
        @message.network.msg @message.replyto, "Roll ##{entry[:rerolls]}:"
      when :note
        @message.network.msg @message.replyto, "Note: #{entry[:text]}"
      when :literal
        @message.network.msg @message.replyto, "#{entry[:text]}"
      end
    end
    @message.network.msg @message.replyto, "==> #{batch.inspect}" if batch.count > 0
  end

  def point_buy_total(rolls)
    total_dnd = -48
    total_pf = 0
    rolls.each do |entry|
      if entry[:type] != :roll
        if entry[:type] == :pointbuy
          total_dnd = -48
          total_pf = 0
        end
        next
      end
      roll = entry[:roll]
      if roll < 3 #roll > 18 or roll < 3
        total_dnd = "invalid"
        total_pf = "invalid"
        break
      end
      if roll < 14
        total_dnd += roll
      else
        total_dnd += 14
        roll.downto(15) { |r| total_dnd += (r-1) / 2 - 5 }
      end
      if roll < 10
        9.downto(roll) { |r| total_pf += r / 2 - 5 }
        #puts "#{roll} #{total_pf}"
      elsif roll < 14
        total_pf += roll - 10
        #puts "#{roll} #{total_pf}"
      elsif roll == 18
        total_pf += 17
        #puts "#{roll} #{total_pf}"
      else
        total_pf += 3
        12.upto(roll) { |r| total_pf += (r-1) / 2 - 5 }
        #puts "#{roll} #{total_pf}"
      end
    end
    rolls << { type: :pointbuy, dnd: total_dnd, pf: total_pf }
  end

  def get_dice_preset(name)
    [ CCCB.instance, @message.network, @message.channel, @message.user ].each do |obj|
      if preset = obj.get_setting( "roll_presets", name )
        return preset
      end
    end
    nil
  end

  def expand_preset( expressions, recursion_check = 0, used = [] )
    catch :restart do
      expressions.each do |expr|
        
        preset = get_dice_preset(expr)

        if recursion_check < 10 and !preset.nil?
          used << expr
          spam "REPLACE: #{expr}, #{expressions.inspect} with #{preset}"
          expressions = replace_expression( expr, expressions, preset )
          spam "RESULT: #{expressions.inspect}"
          recursion_check += 1
          (expressions, used) = expand_preset( expressions, recursion_check, used )
          throw :restart
        end

      end
    end
    spam "EXP: #{expressions.inspect} :: #{used.inspect}"
    return expressions, used
  end

  def replace_expression(expr, expressions, new_expr)
    replacements = new_expr.split( /;/ )
    new_expressions = []
    count = 0
    spam replacements, expr
    while e = expressions.shift
      spam [ new_expressions, e, expressions ].inspect
      if (count += 1)== 1000
        spam "Depth1"
        return
      end
      if e == expr 
        new_expressions += replacements
      else
        new_expressions << e
      end
    end
    new_expressions
  end

  def roll(expression, default, mode)
    success = false
    rolls = []
    processed_expression = []
    until success 
      success = true
      catch :reroll do
        (expressions,used) = expand_preset( expression.split( /;/ ) )
        expression_count = 0
        if used.any? { |e| e.start_with? 'dm_' }
          mode = "dmroll"
        end
        spam expressions.inspect
        processed_expression = expressions.dup
        while expression_count < 30 and expr = expressions.shift
          catch :next_expression do
            if ( expression_count += 1 ) == 30
              rolls << { type: :note, text: "Expressions after the 30th will not be evaluated" }
            end
            spam [ expr, [ expressions ] ].inspect

            gathered = []

            if expr =~ /^(.*?)\s*\*\s*(\d+)\s*$/
              expr = $1
              $2.to_i.downto(2).each { expressions.unshift expr }
            end

            if not rolls.last.nil? and rolls.last[:type] == :roll and expr =~ /^\s*=\s*map\s+(.*)$/
              implicit = 0
              last = rolls.pop
              value = last[:roll]
              $1.split( /,/ ).each do |s|
                implicit += 1
                if s.match /^\s*(\d+)\s*=\s*(.*?)\s*$/ and value == $1.to_i
                  rolls << { type: :literal, text: "#{$2}" }
                  throw :next_expression
                elsif s.match /^\s*(.*?)\s*$/ and value == implicit
                  rolls << { type: :literal, text: "#{$1}" }
                  throw :next_expression
                end
              end

              rolls << last
            end

            if expr =~ /^\s*=(\d+)((?:\s*,\d+)*)\s*$/
              ( $1 + $2 ).split(/,/).each { |n|
                rolls << { type: :roll, roll: n.to_i, detail: [ "user" ] }
              }
              next
            end

            if expr =~ /^\s*=\s*sort\s*$/i
              rolled_rolls = []
              order = []
              rolls.each_with_index do |roll,i|
                next unless roll[:type] == :roll
                rolled_rolls << roll
                order << i
              end
              rolled_rolls.sort { |r2,r1| 
                r1[:roll] <=> r2[:roll]
              }.each do |roll|
                rolls[order.shift] = roll 
              end
              next
            end

            if expr =~ /^\s*=PB(?:\s*(dnd|d&d|pf|pathfinder)?\s*(>|=|<)\s*(-?\d+))?\s*$/i
              unless rolls.last[:type] == :pointbuy
                point_buy_total(rolls)
              end
              if $3
                limit = $3.to_i
                system_max = 96
                system_min = -30
                system = :dnd
                
                if $1 == 'pf' or $1 == 'pathfinder'
                  system = :pf
                  system_max = 102
                  system_min = -7 * 6
                end
              
                if limit >= system_max
                  pb = rolls.pop
                  rolls.push type: :note, text: "Maximum #{system} point buy is #{system_max}" 
                  rolls.push pb
                  limit = system_max
                elsif limit <= system_min
                  pb = rolls.pop
                  rolls.push type: :note, text: "Minimum #{system} point buy is #{system_min}" 
                  rolls.push pb
                  limit = system_min
                end

                #p system: system, max: system_max, min: system_min, limit: limit, action: $2, value: rolls.last[system]
                #p rolls.last
                do_reroll = if $2 == '<' and rolls.last[system] < limit
                  false
                elsif $2 == '>' and rolls.last[system] > limit
                  false
                elsif $2 == '=' and rolls.last[system] == limit
                  false
                else
                  true
                end
                #p "REROLL: #{do_reroll} ( #{$2}, #{ rolls.last[system] < limit }, #{ rolls.last[system] > limit }"

                if do_reroll
                  best = rolls
                  rerolls = if rolls.first[:type] == :reroll 
                    if (limit - rolls.first[:best].last[system]).abs < (limit - rolls.last[system]).abs
                      best = rolls.first[:best]
                    end	
                    rolls.first[:rerolls] + 1
                  else
                    1
                  end
                  spam "Reroll #{rerolls}" 
                  if rerolls > 1000
                    rolls = best
                    rolls.unshift type: :note, text: "Returning the closest result after #{rerolls} attempts. Giving up."
                  else
                    rolls = [ { type: :reroll, rerolls: rerolls, best: best } ]
                    success = false
                    throw :reroll
                  end
                end
              end
            else
              result = dice_string(expr || "d20", default)
              rolls << { type: :roll, roll: result[0], detail: result[1] }
            end
          end
        end
      end
    end

    memory = {
      rolls: rolls,
      expression: processed_expression,
      mode: mode,
      msg: @message,
      jinx: @dice_current_jinx == :applied_jinx,
      access: Time.now
    }
    
    @message.network.persist[:dice_memory] ||= []
    @message.network.persist[:dice_memory].unshift memory
    @message.network.persist[:dice_memory].pop if @message.network.persist[:dice_memory].count > 100
    (@message.user.persist[:dice_memory_saved] ||= {})["current"] = @message.network.persist[:dice_memory].first

    if @dice_current_jinx == :applied_jinx
      @message.user.persist[:dice_jinx] = false
    end
    return rolls
  end

end

module CCCB::Core::Dice
  extend Module::Requirements

  def module_load
    add_setting :user, "roll_presets"
    add_setting :channel, "roll_presets"
    add_setting :network, "roll_presets"
    add_setting :core, "roll_presets"

    set_setting( "d20", "options", "default_die")

    add_request :dice, /^\s*jinx\s+(\S)+\s*$/i do |match, message|
      message.user.persist[:dice_jinx] ||= true
      match[1].downcase == "me" ? "Ok" : "Ok, #{nick} has been jinxed"
    end

    add_request :dice, /^\s*am\s+I\s+jinxed\s*\??\s*$/i do |m, s|
      if message.user.persist[:dice_jinx]
        "Yes"
      else
        "No. Any bad luck is your own"
      end
    end


    add_request :dice, /^\s*list\s+(?:(?:my|(\S+?)(?:'s))?\s+)?memories/i do |match,message| 
      if message.user.persist[:dice_memory_saved]
        memories = message.user.persist[:dice_memory_saved].sort { |(n1,r1),(n2,r2)| 
          r1[:access] <=> r2[:access] 
        }.map { |n,r| n }.join( ", " )

        "I found: #{memories}"
      else
        "None."
      end
    end

    add_request :dice, /^
        (?<command>toss|qroll|roll|dmroll)
        (?:\s+
          (?<expression>.*?)
        )?
        (?:
          \s+w(?:ith|\/)\s*
          (?:
            (?<advantage>a(?:dv(?:antage)?)?)
            |
            (?<disadvantage>d(?:is(?:adv(?:antage)?)?)?)
          )
        )?
        \s*
      $
    /ix do |match, message|
      # m, s, mode, nick, expression, modifier|
      #p [ m, s, mode, nick, expression, modifier ]

      mode = match[:command]
      mode = 'qroll' if mode == 'toss'

      default_die = message.user.get_setting("options", "default_die")
      default = if match[:advantage]
        "2#{default_die} dl"
      elsif match[:disadvantage]
        "2#{default_die} dh"
      else
        "1#{default_die}"
      end

      roller = CCCB::DieRoller.new(message)
      rolls = roller.roll( match[:expression], default , mode)
      roller.message_die_roll(message.nick, rolls, mode)

      nil
    end

    add_request :dice, /^\s*
      
      (?:
        (?:
          (?<user> my | \S+? ) (?: 's)? \s+ 
        )?
        (?<index>\d+ (?:th|st|rd|nd)|last|first) \s+ roll
      |
        recall \s+ 
        (?: 
          (?<user> \S+? )(?:'s)? \s+
        )? 
        (?<memory> \w+)
      )
      (?<detail> \s+ in \s+ detail)?
      \s*$
    /ix do |match, message| 
      # |m, s, by_user, n, recall_user, recall, detail|
      user = nil
      selected = if match[:index]
        list = message.network.persist[:dice_memory].dup
        if match[:user]
          user = if match[:user] == 'my'
            message.user
          else
            message.network.users[match[:user].downcase]
          end
          spam "Selecting on #{user}"

          list.select! { |l| l[:msg].user.id == user.id }
        elsif message.to_channel?
          list.select! { |l| l[:msg].replyto.downcase == message.replyto.downcase }
        end
        index = if match[:index] == 'last'
          0
        elsif match[:index] == 'first'
          list.count - 1
        elsif match[:index] == "0th"
          list.count + 10
        else
          match[:index].gsub(/[^\d]/,'').to_i - 1
        end

        user ||= list[index][:msg].user
        list[index]
      elsif match[:memory]
        user = if match[:user]
          message.network.users[match[:user].downcase]
        else
          message.user
        end

        if user.persist[:dice_memory_saved] and user.persist[:dice_memory_saved].include? match[:memory]
          user.persist[:dice_memory_saved][recall]
        end
      end

      if selected
        mode = if match[:detail]
          "roll"
        else
          'qroll'
        end

        (user.persist[:dice_memory_saved] ||= {})["current"] = selected

        jinx = if selected[:jinx]
          "While jinxed, "
        else 
          ""
        end

        location = if selected[:msg].to_channel?
          selected[:msg].replyto
        else
          "query"
        end

        message.network.msg message.replyto, "#{ jinx }#{selected[:msg].nick} rolled #{selected[:expression].join("; ")} in #{location} on #{selected[:msg].time} and got: (m:#{mode})"
        CCCB::DieRoller.new(message).message_die_roll( message.nick, selected[:rolls], mode )
        nil
      else
        "I can't find that."
      end
    end

    add_request :dice, /^\s*forget\s+(?<name>\w+)/i do |match, message|
      if message.user.persist[:dice_memory_saved]
        if message.user.persist[:dice_memory_saved][match[:name]]
          message.user.persist[:dice_memory_saved].delete match[:name]
          "Done."
        else
          "It seems already to have been done."
        end
      else
        "That would require you to have rolled dice."
      end
    end

    add_request :dice, /^\s*remember\s+that\s+as\s+(?<name>\w+)/i do |match, message|
      preset = match[:name]
      if message.user.persist[:dice_memory_saved]
        if message.user.persist[:dice_memory_saved]["current"]
          lru = message.user.persist[:dice_memory_saved].sort { |(n1,r1),(n2,r2)| r1[:access] <=> r2[:access] }
          if message.user.persist[:dice_memory_saved].count > 9
            message.user.persist[:dice_memory_saved].delete(lru.first[0])
            message.network.msg message.replyto, "Deleted #{lru.first[0]}. #{lru[1][0]} will be deleted next"
          elsif message.user.persist[:dice_memory_saved].count == 9
            message.network.msg message.replyto, "#{lru.first[0]} will be deleted if you store one more"
          end
          (message.user.persist[:dice_memory_saved] ||= {})[name] = message.user.persist[:dice_memory_saved]["current"]
          "Done."
        else
          "Sorry, I don't remember your roll"
        end
      else
        "I can't recall you ever rolling dice"
      end
    end

    add_help(
      :dice, 
      "dice",
      "Commands for rolling dice",
      [
        "pick a subtopic (use 'help subtopic' to view):",
        "dice_commands     : roll, dmroll, qroll, etc",
        "dice_exp_simple   : Expression syntax (simple)",
        "dice_exp_complex  : Expression syntax (modifiers and specials)",
        "roll_presets      : Saving and using presets",
        "dice_memory       : Recalling and storing rolls",
      ],
      :none
    )

    add_help(
      "dice_commands",
      "roll, dmroll, qroll, etc",
      [
        "!roll   : Returns long-form results by default with individual rolls",
        "!qroll  : Returns compact results",
        "Generally, a dice command will be '!roll <expression>' - see dice_exp_simple for more"
      ],
      :info
    )
    add_help(
      "dice_exp_simple",
      "roll, dmroll, qroll, etc",
      [
        "Syntax: [q]roll <EXPRESSION> [<MODIFIER>] ([] indicates an optional part)",
        "EXPRESSION: (<DICE>|<PRESET>|<SPECIAL>)[*<multiplier>][;<EXPRESSION>]",
        "multiplier: generate <multiplier> copies of the EXPRESSION",
        "DICE: [ NdX ][(dl|dh|rA[,B])] + C",
        "  (N dice, size X, add C afterwards)",
        "  dl: Drop the lowest. dh: Drop the highest. ",
        "  (use 'd2h' to drop the two highest, etc)",
        "  rA[,B]: reroll any values less than A up to B (defaults to 1) times",
        "PRESET: [<nick>::]<preset_name>",
        "  (stored previously)",
        "SPECIAL: See dice_exp_complex",
        "MODIFIER: [ w/adv | w/dis ] Change the default die from 1d20 to 2d20dl and 2d20dh"
      ],
      :info
    )
    add_help(
      "dice_exp_complex",
      "roll, dmroll, qroll, etc",
      [
        "=N1,N2,N3,...Nn",
        "  Returns the given list",
        "=map value1,value2,...,valueN",
        "  Alters the last value (N) to be the Nth item in the map list",
        "=PB [(dnd|pf) (<|=|>) <number>]",
        "  Calculate the dnd and pathfinder point-buy equivalent of the previous",
        "  six rolls. Optionally with a condition - if the condition is not met,",
        "  the entire expression will be rerolled"
      ],
      :info
    )
    add_help(
      "roll_presets",
      "roll, dmroll, qroll, etc",
      [
        "!set <name> <value>",
        "  sets <name> as a preset, which can be used in an expression",
        "!set <name>",
        "  unsets <name> for your user",
      ],
      :info
    )

    add_help(
      "dice_memory",
      "Recalling and storing rolls",
      [
        "![my | <nick>'s] ( last | first | N(th|st|rd|nd) ) roll",
        "  With 'my' or a nick, return that person's last, first or Nth",
        "  dice roll. Without, return the last, first or Nth in the current",
        "  channel",
        "!recall [ <nick>'s ] <name>",
        "  Recall a stored result by name. Results are stored per nick,",
        "  Each nick can store 10 named results, plus 'current' which is",
        "  set to whatever roll you last made or result you last looked",
        "  at with the two commands above.",
        "You may append 'in detail' to either of the above commands to see",
        "the full expanded results of a roll",
        "!remember that as <name>",
        "  Store whatever roll is held in your 'current' preset as <name>",
      ],
      :info
    )
  end
end
