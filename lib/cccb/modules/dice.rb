require 'securerandom'
require 'densities'
require 'd20code'

class CCCB::DieRoller

  def initialize(message, callbacks: true)
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
    @expression_cache = {}
    @run_callbacks = callbacks
  end

  def self.dice_colour( max, roll )
    if roll == 1
      "\x03" + "041" + "\x0F"
    elsif roll > max
      "\x03" + "03#{roll}" + "\x0F!"
    elsif roll == max
      "\x03" + "11#{roll}" + "\x0F"
    else
      roll
    end
  end

  def self.is_expression?(expression)
    begin
      info "Is_expression? #{expression}"
      !! Dice::Parser.new( expression )
    rescue Dice::Parser::Error => e
      false
    rescue Dice::Parser::NoModifier => e
      false
    end
  end

  def message_die_roll(nick, rolls, mode )
    compact = ( (mode != 'roll') || (@roll_style == :compact) )
    batch = []
    if rolls.is_a? Exception
      @message.reply "Error: #{rolls.message}"
      return
    end

    rolls.each do |entry|
      #p "EN:", entry, mode, compact
      if compact and entry[:type] != :roll and not batch.empty?
        @message.reply "==> #{batch.inspect}"
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
        replytext = if mode == 'roll'
          "#{entry[:detail]} ==> #{entry[:roll]}"
        end
        @message.reply replytext
      when :pointbuy
        @message.reply "Point-buy equivalent: D&D 3e-4e #{entry[:dnd]}, D&D 5e #{entry[:dnd5e]}, Pathfinder #{entry[:pf]}"
      when :reroll
        @message.reply "Roll ##{entry[:rerolls]}:"
      when :note
        @message.reply "Note: #{entry[:text]}"
      when :literal
        @message.reply "#{entry[:text]}"
      end
    end
    @message.reply "==> #{batch.inspect}" if batch.count > 0
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
    total_dnd5e = total_pf + 12
    rolls << { type: :pointbuy, dnd: total_dnd, dnd5e: total_dnd5e, pf: total_pf }
  end

  def get_dice_preset(name)
    [ CCCB.instance, @message.network, @message.channel, @message.user ].each do |obj|
      next if obj.nil?
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

  def dice_string(expression, default)
    detail "Roll #{expression.inspect}, default #{default.inspect}"
    parser = if @expression_cache.include? expression
      @expression_cache[expression]
    else
      debug "New parser: #{expression} with default #{default}"
      @expression_cache[expression] = Dice::Parser.new( expression, default: default ) 
    end
    parser.roll
    output = if @run_callbacks
      parser.output( self.callbacks) 
    else
      parser.output( {} )
    end
    [ parser.value, output ]
  end

  def callbacks
    {
      fudge: Proc.new do |obj, roll|
        { -1 => :-, 0 => :" ", +1 => '+' }[roll]
      end,
      die: Proc.new do |obj, roll|
        CCCB::DieRoller.dice_colour( obj.size, roll )
      end
    }
  end

  def processed_expression(expression)
    (expressions,used) = expand_preset( expression.split( /;/ ) )
    spam expressions.inspect
    return expressions.dup
  end

  def roll(expression, default, mode)
    success = false
    expression ||= ""
    rolls = []
    expressions = processed_expression(expression)
    until success 
      success = true
      catch :reroll do
        expression_count = 0
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

            if expr =~ /^\s*=PB(?:\s*(dnd|next|5e|d&d5e|d&dnext|d&d|pf|pathfinder)?\s*(>|=|<)\s*(-?\d+))?\s*$/i
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
                elsif $1 == '5e' or $1 == 'd&d5e' or $1 == 'next' or $1 == 'd&dnext'
                  system = :dnd5e
                  system_max = 114
                  sysemt_min = -5 * 6
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

    return rolls
  end

end

module CCCB::Core::Dice
  extend Module::Requirements

  needs :bot, :background, :api_core

  ADVANTAGE_REGEX = /
    \s*
    w (?:ith)?
    \s*
    (?: \/ \s* )?
    (?: 
      (?<advantage> a (?: dv (?: antage )? )? )
    |
      (?<disadvantage> d (?: is (?: adv (?: antage )? )? )? )
    )
    \s*
    (?: ; | $ )
  /x

  def add_dice_memory(message, memory)
    memory_limit = message.network.get_setting( "options", "dice_memory_limit" ).to_i
    message.network.persist[:dice_memory] ||= []
    message.network.persist[:dice_memory].unshift memory
    message.network.persist[:dice_memory].pop while message.network.persist[:dice_memory].count > memory_limit
    (message.user.persist[:dice_memory_saved] ||= {})["current"] = message.network.persist[:dice_memory].first
  end

  def module_load
    add_setting :user, "roll_presets"
    add_setting :channel, "roll_presets"
    add_setting :network, "roll_presets"
    add_setting :core, "roll_presets"

    set_setting( "d20", "options", "default_die")
    default_setting( 4, "options", "probability_graph_height" )
    default_setting( 20, "options", "probability_graph_width" )
    default_setting( "0.00", "options", "probability_graph_cutoff" )
    default_setting( "_.=m#@", "options", "probability_graph_chars" )
    default_setting( 2048, "options", "dice_memory_limit" )

    add_help_topic( 'dice_expressions',
      "# Dice Expressions",
      "## Simple expressions",
      "The simplest expressions are of the form 'XdY + Z', where X, Y and Z are numbers. In fact, the XdY part can be left off if the die is the default for the channel - usually 1d20",
      "## Compound expressions",
      "Multiple rolls can be joined together, either by using (for instance) '4d6dl * 6' to make six seperate rolls of '4d6dl' or by joining rolls with a semicolon. '4d6dl; 4d6dl; 4d6dl; 4d6dl; 4d6dl; 4d6dl' is equivalent to '4d6dl * 6'.",
      "## Modifying the default (Advantage and Disadvantage)",
      "When using the simplest '+Z' form, taking the default die (usually a d20), the command can be modified to use either advantage (roll twice and take the highest) or disadvantage (roll twice and take the lowest). This is done by appending 'w/a' or 'w/d' to the command - e.g.: '!roll +3 w/a' '!roll +10 w/d'.",
      "The modifier changes the default die for that roll, so it will apply even to more complex rolls, so long as they do not specify the die type, so a roll such as '!roll +3;1d10+2 w/a' will apply advantage to the +3 part, but leave the '1d10+2' alone.",
      "## Storing presets",
      "Any user can store presets on their own user account with the !preset command. Presets can be stored at the channel or network level, but only by users who have the rights to do so. An example preset might be '!preset attack +5; 1d10+3' to store an attack roll (+3) and the subsequent damage roll (which can be ignored if the attack fails). After this, the user who created this setting can roll their attack with '!roll attack' (and even '!roll attack w/a' or '!roll attack w/d'). Presets can be displayed by using the '!preset' command and unset with '!preset attack' (to unset a preset called 'attack').",
      "## Modifiers",
      "The dicebot supports many modifiers. Here are most of them:",
      "---",
      "| Modifier | Example | Result |",
      "| ----- | ----- | ----- |",
      "| f | 4df | Fudge/FATE dice |",
      "| dlN | 4d6dl | Drops the lowest N (or 1, if it is omitted) results. |",
      "| dhN | 4d6dl | Drops the highest N (or 1, if it is omitted) results. |",
      "| khN | 3d10kh | Keeps only the highest N (or 1, if it is omitted) results. |",
      "| klN | 2d4kl | Keeps only the lowest N (or 1, if it is omitted) results. |",
      "| sN | 3d10s8 | Counts successes greater then or equal to N. |",
      "| fN | 3d10s8f1 | Usually used with the 's' modifier. Counts values of N as -1. |",
      "| rN | 1d10r1 | Reroll any values of N. |",
      "| roN | 2d6ro2 | Reroll values of N once (Currently breaks probability code). |",
      "| ! | 4d10! | Exploding: When a die rolls the maximum, add another die (as a distinct roll). |",
      "| !! | 4d10!! | Compounding: When a die rolls the maximum, add the roll of another die. |",
      "| !p | 4d10!p | Penetrating: When a die rolls the maximum, subtrace 1 and add the roll of another die. |",
      "| w  | 3d10w | White Wolf. Shorthand for !f1s8. (Exploding, fail on 1 (-1), success on 8 or more (+1)). |",
      "! wN | 7d10s6 | White Wolf style roll, but with success on N rather than the default 8. |",
      "---",
    )

    @doc
    # Returns past rolls that the user has saved.
    add_command :dice, "dice memory show" do |message, (user)|
      message.reply( if message.user.persist[:dice_memory_saved]
        memories = message.user.persist[:dice_memory_saved].sort { |(n1,r1),(n2,r2)| 
          r1[:access] <=> r2[:access] 
        }.map { |n,r| n }.join( ", " )

        "I found: #{memories}"
      else
        "None."
      end )
    end

    #@doc
    # Returns the average of a dice expression
    # See %(help:dice_expressions) for more information
    add_command :dice, "average" do |message, (expression)|
      raise "Of what?" if expression.nil?
      default = if message.to_channel?
        message.replyto.get_setting( "roll_presets", "default_die" )
      else
        message.user.get_setting( "roll_presets", "default_die" )
      end
      parser = Dice::Parser.new( expression, default: default )
      average = Backgrounder.new(parser).background(:average)
      message.reply "The average of #{expression} is #{average}"
    end
      
    #@doc
    # Probability expressions
    # Usage: 
    # * prob [dice_expression]
    #    - Displays a graph of the probability of the dice expression
    # 
    # * prob [dice_expression] [comparator] [dice_expression]
    #    - Compares too dice expressions. Comparators can be >, >=, < or <=.
    #    - e.g.: !prob 4d6dl > 3d6 (62.22%)
    # See %(help:dice_expressions) for more information
    add_command :dice, "prob" do |message, (exp1, symbol, exp2)|
      raise "Of what?" if exp1.nil?
        
      default = if message.to_channel?
        message.replyto.get_setting( "roll_presets", "default_die" )
      else
        message.user.get_setting( "roll_presets", "default_die" )
      end
      parser1 = Dice::Parser.new( exp1, default: default )
      density1 = Backgrounder.new(parser1).background(:density)

      if symbol.nil?

        graph_height = message.replyto.get_setting( "options", "probability_graph_height" ).to_i 
        graph_width = message.replyto.get_setting( "options", "probability_graph_width" ).to_i
        graph_chars = message.replyto.get_setting( "options", "probability_graph_chars" )
        graph_cutoff = message.replyto.get_setting( "options", "probability_graph_cutoff" )
        raise "Invalid graph cutoff '#{graph_cutoff}': Must be a number (with optional decimal)" unless graph_cutoff.match /^\d+(?:\.\d+)?/

        # '▁▂▃▄▅▆▇█'
        # '▁▂▃▄▅▆▇█'
        # "_.-=#8"
        graph_distinctions = graph_chars.each_char.map.with_index { |c,i| [ c, Rational(i+1,graph_chars.length) ] }.reverse

        lowest = density1.map(&:first).min
        highest = density1.map(&:first).max
        lowest.upto(highest).each do |i|
          next if density1.map(&:first).include? i
          density1.d[i] = 0
        end
        density1 = density1.sort { |a,b| a.first <=> b.first }

        state = :start
        decimals = graph_cutoff.reverse.index('.')
        temp = []
        density1 = density1.each_with_object([]) do |(i,p),a|
          probability = "%.#{decimals}f" % (p.to_f * 100)
          #p "PR: #{i} :: #{state.inspect} :: #{p} :: #{probability} > #{graph_cutoff}"
          if probability > graph_cutoff
            case state
            when :start
              state = :middle
            when :end?
              state = :middle
              a += temp
              temp = []
            end
            a << [i,p]
          else
            case state
            when :middle
              state = :end?
              a << [i,p]
            when :end?
              temp << [i,p]
            end
          end
        end

        graph_scale = 1
        graph_scale += 1 while ((graph_scale + 1) * density1.count) <= graph_width
        max_prob = density1.map(&:last).max
        output = (1..graph_height).map {|i|
          sprintf("% 6.2f%%|",(max_prob * 100 * i/graph_height.to_f)) + density1.map { |n,p|
            x = p * (1/max_prob) * graph_height
            if char = graph_distinctions.find { |(c,fraction)| x >= i - (1-fraction) }
              if p == max_prob
                "\x02" + char[0] * graph_scale + "\x02"
              else
                char[0] * graph_scale
              end
            elsif n == 0
              " " * ((graph_scale-1)/2) + "|" * (graph_scale.odd? ? 1 : 2 ) + " " * ((graph_scale-1)/2) 
            else
              ' ' * graph_scale
            end 
          }.join
        }
        nums = density1.map(&:first).map(&:to_s)
        last_row = "       |" + " " * (nums.count * graph_scale)
        legend = [ "", last_row ]
        line_piece = "-" * ((graph_scale-1)/2)
        legend[0] = ([ "       |" ] + density1.map.with_index { |(num,p),i|
          colour_start = ""
          colour_end = ""
          if p == max_prob
            colour_start = "\x02"
            colour_end = "\x02"
          end
          n = num.to_s
          i = (i + 1) * graph_scale
          line_piece + colour_start + if n == '0'
            last_row[ 8 + i - graph_scale, graph_scale ] = " " * ((graph_scale-1)/2) + "|" * (graph_scale.odd? ? 1 : 2 ) + " " * ((graph_scale-1)/2) 
            "|" * (graph_scale.odd? ? 1 : 2 )
          elsif n.end_with? '0'
            if n.start_with? '-'
              last_row[ 8 + i - (n.length - 1) - graph_scale/2, n.length - 1 ] = n[1..-1].reverse
            else
              last_row[ 8 + i - (graph_scale+1)/2, n.length - 1 ] = n
            end
            if n.start_with? '-'
              '!' + (graph_scale.even? ? '-' : '')
            else
              (graph_scale.even? ? '-' : '') + '!'
            end
          else
            if n.start_with? '-'
              n[-1] + (graph_scale.even? ? '-' : '')
            else
              (graph_scale.even? ? '-' : '') + n[-1]
            end
          end + colour_end + line_piece
        }).join
        
        message.reply output.reverse.reject { |r| r.match /^\s+$/ } + legend
        next
      end
      
      sym = case symbol
      when 'gt'
        :>
      when 'eq', '='
        :==
      when 'lt'
        :<
      when 'le'
        :<=
      when 'ge'
        :>=
      when '<=', '<', '==', '>', '>='
        symbol.to_sym
      else
        raise "Unknown comparison symbol: #{symbol}"
      end
      
      parser2 = Dice::Parser.new( exp2, default: "+0" )
      density2 = Backgrounder.new(parser2).background(:density)
      density = density1 - density2
      rational = density.send(sym, 0)

      message.reply( if density.exact
        "Probability: %s (%.2f%%)" % [ rational.to_s, rational.to_f * 100 ]
      else
        "Probability: ~%.2f%% (exact results unavailable)" % [ rational.to_f * 100 ]
      end )
    end

    #@doc
    #@param q String A dice expression
    # Returns the result of a dice expression
    # See %(help:dice_expressions) for more information
    register_api_method :dice, :roll do |**args|
      roller = CCCB::DieRoller.new(args[:__message], callbacks: false )
      #roller.roll(args[:q],"1d20","roll")
      Backgrounder.new(roller).background(:roll, args[:q], "1d20", 'roll')
    end
  
    roll_stack = {}
    #@doc
    # Returns the result of a dice expression
    # See %(help:dice_expressions) for more information
    add_command :dice, [%w{toss qroll roll dmroll}] do |message, args, words|
      begin
        roll_stack[message.replyto] ||= 0
        this_roll = roll_stack[message.replyto] += 1
        mode = words.last == 'toss' ? 'qroll' : words.last
        expression = args.join(" ")

        default_die = message.user.get_setting("options", "default_die")
        while match = ADVANTAGE_REGEX.match(expression)
          default = if match
            from,to = match.offset(0)
            start = expression[0..from].rindex(';')||0
            expression[from, to-from] = ""
            this_expression = expression[start..from]
            if match[:advantage]
              "2#{default_die}dl"
            elsif match[:disadvantage]
              "2#{default_die}dh"
            end
          else
            "1#{default_die}"
          end
        end

        #roller = api(
        #  :"core.background", 
        #  object: CCCB::DieRoller.new(message),
        #  methods: [ :roll ]
        #)
        roller = CCCB::DieRoller.new(message)
        rolls = roller.roll( expression, default, mode)
        debug "Got rolls: #{rolls}"
        reply = roller.message_die_roll(message.nick, rolls, mode)
        if roll_stack[message.replyto] > 1 
          message.reply reply.map do |l|
            "#{message.replyto}: (#{this_roll}): #{l}"
          end
        else
          message.reply reply
        end

        memory = {
          rolls: rolls,
          expression: roller.processed_expression(expression),
          mode: mode,
          msg: message,
          access: Time.now
        }
        add_dice_memory(message, memory)
      ensure
        roll_stack[message.replyto] -= 1
      end
    end

    #@doc
    # Shows the stored history of dice rolls.
    # examples: 
    # * dice history show my last
    #   - Show your last roll, abbreviated
    # * dice history show my 3rd in detail
    #   - Show your third-from last roll, in full detail
    # * dice history show ccooke's last
    #   - Show the last roll by user 'ccooke', abbreviated
    # * dice history show stored foo
    #   - Show a stored roll on my user named 'foo', abbreviated
    # Sets the 'current' roll for this channel or query, which can be used to save the roll to a named history slot on your user object.
    add_command :dice, "dice history show" do |message, args|
      match = /^\s*
        (?:
          (?:
            (?<user> my | \S+? ) (?: 's)? \s+ 
          )?
          (?<index>\d+ (?:th|st|rd|nd)|last|first)
        |
          stored \s+ 
          (?: 
            (?<user> \S+? )(?:'s)? \s+
          )? 
          (?<memory> \w+)
        )
        (?<detail> \s+ in \s+ detail)?
        \s*$
      /ix.match( args.empty? ? "my last" : args.join(' ') )
      user = nil
      selected = if match[:index]
        #p message.network.persist[:dice_memory]
        list = message.network.persist[:dice_memory].dup
        if match[:user]
          user = if match[:user] == 'my'
            message.user
          else
            if submatch = match[:user].match( /^n\((\w+)\)::(.*)$/ )
              CCCB.instance.networking.networks[submatch[1]].users[submatch[2].downcase]
            else
              message.network.users[match[:user].downcase]
            end
          end
          spam "Selecting on #{user}"

          list.select! { |l| l[:msg].user.id == user.id }
        elsif message.to_channel?
          list.select! { |l| l[:msg].replyto.to_s.downcase == message.replyto.id }
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
        
        next "No such roll" if list.empty?
        user ||= list[index][:msg].user
        list[index]
      elsif match[:memory]
        user = if match[:user]
          message.network.users[match[:user].downcase]
        else
          message.user
        end

        if user.persist[:dice_memory_saved] and user.persist[:dice_memory_saved].include? match[:memory]
          user.persist[:dice_memory_saved][match[:memory]]
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

        message.reply "#{ jinx }#{selected[:msg].nick} rolled #{selected[:expression].join("; ")} in #{location} on #{selected[:msg].time} and got: (m:#{mode})"
        CCCB::DieRoller.new(message).message_die_roll( message.nick, selected[:rolls], mode )
        nil
      else
        "I can't find that."
      end
    end

    add_hook :dice, :pre_setting_set do |object, setting, hash|
      next unless setting == "roll_presets"

      hash.keys.each do |key|
        next if hash[key].nil?
        if CCCB::DieRoller.is_expression? key
          hash[key] = "=1; =map Cheat :-)"
        end
      end
    end

    add_hook :dice, :pre_setting_set do |object, setting, hash|
      next unless setting == "options"
      next unless hash.include? "default_die"

      if hash["default_die"] =~ /^\s*1?\s*d\s*(\d+)\s*$/
        hash["default_die"] = "d#{$1}"
      elsif not hash["default_die"].nil?
        raise "Invalid default die: #{hash["default_die"]}"
      end
    end

    #@doc
    # Displays, sets and unsets roll presets for a user
    # See %(help:dice_expressions) for more information
    add_command :dice, "preset" do |message,args|
      target = case args[0]
      when "my"
        args.shift
        :user
      when "network"
        args.shift
        :network
      when "global"
        args.shift
        :core
      when "channel"
        args.shift
        :channel
      else
        :user
      end

      name = args.shift

      if name == "list" or name.nil?
        preset = nil
        setting = "#{target}::roll_presets"
      else
        preset = args.join(" ") || ""
        setting = "#{target}::roll_presets::#{name}"
      end

      message.reply user_setting( message, setting, preset )
    end

    #@doc
    # Remove a named roll from your user history
    add_command :dice, "dice history forget" do |message, (name)|
      message.reply( if message.user.persist[:dice_memory_saved]
        if message.user.persist[:dice_memory_saved][name]
          message.user.persist[:dice_memory_saved].delete name
          "Done."
        else
          "It seems already to have been done."
        end
      else
        "That would require you to have rolled dice."
      end )
    end

    #@doc
    #@param name String A name
    # Stores the 'current' roll (either the last result of the roll command or something recalled with the 'dice history show' command) in your user. Users have space to store ten named rolls; storing the eleventh will cause the least accessed one to fall off the list
    add_command :dice, "dice history store" do |message, (name)|
      preset = name
      message.reply( if message.user.persist[:dice_memory_saved]
        if message.user.persist[:dice_memory_saved]["current"]
          lru = message.user.persist[:dice_memory_saved].sort { |(n1,r1),(n2,r2)| r1[:access] <=> r2[:access] }
          if message.user.persist[:dice_memory_saved].count > 9
            message.user.persist[:dice_memory_saved].delete(lru.first[0])
            message.reply "Deleted #{lru.first[0]}. #{lru[1][0]} will be deleted next"
          elsif message.user.persist[:dice_memory_saved].count == 9
            message.network.msg message.replyto, "#{lru.first[0]} will be deleted if you store one more"
          end
          (message.user.persist[:dice_memory_saved] ||= {})[preset] = message.user.persist[:dice_memory_saved]["current"]
          "Done."
        else
          "Sorry, I don't remember your roll"
        end
      else
        "I can't recall you ever rolling dice"
      end )
    end

  end
end
