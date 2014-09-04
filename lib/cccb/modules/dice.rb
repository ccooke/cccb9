require 'securerandom'
require 'densities'
require 'd20code'

class CCCB::DieRoller

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
    @expression_cache = {}
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
        @message.reply "Point-buy equivalent: D&D #{entry[:dnd]}, D&D Next: #{entry[:dnd5e]}, Pathfinder #{entry[:pf]}"
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

  def dice_string(expression, default)
    parser = if @expression_cache.include? expression
      @expression_cache[expression]
    else
      info "New parser: #{expression} with default #{default}"
      @expression_cache[expression] = Dice::Parser.new( expression, default: default ) 
    end
    parser.roll
    [ parser.value, parser.output( self.callbacks ) ]
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

  def roll(expression, default, mode)
    success = false
    expression ||= ""
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

  ADVANTAGE_REGEX = /
    w (?:ith)?
    \s*
    (?: 
      (?<advantage> a (?: dv (?: antage )? )? )
    |
      (?<disadvantage> d (?: is (?: adv (?: antage )? )? )? )
    )
    \s*
    $
  /x

  def module_load
    add_setting :user, "roll_presets"
    add_setting :channel, "roll_presets"
    add_setting :network, "roll_presets"
    add_setting :core, "roll_presets"

    set_setting( "d20", "options", "default_die")
    default_setting( 4, "options", "probability_graph_height" )
    default_setting( 20, "options", "probability_graph_width" )
    default_setting( "_.=m#@", "options", "probability_graph_chars" )
  
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

    add_command :dice, "prob" do |message, (exp1, symbol, exp2)|
      raise "Of what?" if exp1.nil?
        
      default = if message.to_channel?
        message.replyto.get_setting( "roll_presets", "default_die" )
      else
        message.user.get_setting( "roll_presets", "default_die" )
      end
      parser1 = Dice::Parser.new( exp1, default: default )


      if symbol.nil?
        graph_height = message.replyto.get_setting( "options", "probability_graph_height" ).to_i 
        graph_width = message.replyto.get_setting( "options", "probability_graph_width" ).to_i
        graph_chars = message.replyto.get_setting( "options", "probability_graph_chars" )

        density = parser1.density
        lowest = density.map(&:first).min
        highest = density.map(&:first).max
        lowest.upto(highest).each do |i|
          next if density.map(&:first).include? i
          density.d[i] = 0
        end
        density = density.sort { |a,b| a.first <=> b.first }
        graph_scale = 1
        graph_scale += 1 while ((graph_scale + 1) * density.count) <= graph_width
        max_prob = density.map(&:last).max
        output = (1..graph_height).map {|i|
          sprintf("% 6.2f%%|",(max_prob * 100 * i/graph_height.to_f)) + density.map { |n,p|
            x = p * (1/max_prob) * graph_height
            if x >= i && p == max_prob
              "\x02" + graph_chars[5]*graph_scale + "\x02"
            elsif x >= i
              graph_chars[5] * graph_scale
            elsif x >= i - 0.20
              graph_chars[4] * graph_scale
            elsif x >= i - 0.40
              graph_chars[3] * graph_scale
            elsif x >= i - 0.60
              graph_chars[2] * graph_scale
            elsif x >= i - 0.90
              graph_chars[1] * graph_scale
            elsif x >= i - 0.99
              graph_chars[0] * graph_scale
            elsif n == 0
              " " * ((graph_scale-1)/2) + "|" * (graph_scale.odd? ? 1 : 2 ) + " " * ((graph_scale-1)/2) 
            else
              ' ' * graph_scale
            end 
          }.join
        }
        nums = density.map(&:first).map(&:to_s)
        last_row = "       |" + " " * (nums.count * graph_scale)
        legend = [ "", last_row ]
        line_piece = "-" * ((graph_scale-1)/2)
        legend[0] = ([ "       |" ] + density.map.with_index { |(num,p),i|
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
        
        message.reply output.reverse.reject { |r| r.match /^\s+$/ }
        message.reply legend
        next
      end
      
      sym = case symbol
      when 'gt'
        :>
      when 'eq'
        :==
      when 'lt'
        :<
      when 'le'
        :<=
      when 'ge'
        :>=
      else
        raise "Unknown comparison symbol: #{symbol}"
      end
      
      parser2 = Dice::Parser.new( exp2, default: "+0" )
      density = parser1.density - parser2.density
      rational = density.send(sym, 0)

      message.reply( if density.exact
        "Probability: %s (%.2f%%)" % [ rational.to_s, rational.to_f * 100 ]
      else
        "Probability: ~%.2f%% (exact results unavailable)" % [ rational.to_f * 100 ]
      end )
    end

    add_command :dice, [%w{toss qroll roll dmroll}] do |message, args, words|
      mode = words.last == 'toss' ? 'qroll' : words.last
      expression = args.join(" ")

      match = ADVANTAGE_REGEX.match(expression)
      default_die = message.user.get_setting("options", "default_die")
      default = if match
        if match[:advantage]
          "2#{default_die}dl"
        elsif match[:disadvantage]
          "2#{default_die}dh"
        end
      else
        "1#{default_die}"
      end

      roller = CCCB::DieRoller.new(message)
      rolls = roller.roll( expression, default , mode)
      message.reply roller.message_die_roll(message.nick, rolls, mode)
    end

    add_command :dice, "history show" do |message, args|
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

    add_command :dice, "preset" do |message,args|
      target = case args[0]
      when "my"
        args.shift
        :user
      when "channel"
        args.shift
        :channel
      else
        :user
      end

      name = args.shift
      preset = args.join(" ")
      message.reply user_setting( message, target, "roll_presets", name, preset || "" )
    end

    add_command :dice, "history forget" do |message, (name)|
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

    add_command :dice, "history store" do |message, (name)|
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
      :dice,
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
      :dice,
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
      :dice,
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
      :dice,
      "roll_presets",
      "roll, dmroll, qroll, etc",
      [
        "!preset <name> <value>",
        "  sets <name> as a preset, which can be used in an expression",
        "!preset <name>",
        "  unsets <name> for your user",
      ],
      :info
    )

    add_help(
      :dice,
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


    CCCB::ContentServer.add_keyword_path('dice') do |network,session,match|
      expression = match[:call].split('/').join(';')
      expression.gsub(/;\s*$/,'')
      message = CCCB::Message.new( network, "PRIVMSG d20 :roll #{expression}", true )
      p message
      message.instance_variable_set(:@content_server_strings, [])
      def message.reply(reply)
        puts "M: #{reply}"
        @content_server_strings << reply
      end
      roller = CCCB::DieRoller.new( message )
      rolls = roller.roll(expression, "1d20", "roll")
      roller.message_die_roll("system", rolls, "roll")
      { 
        template: :plain_text,
        text: message.instance_variable_get(:@content_server_strings).join("\n").gsub(/\x03..(.*?)\x0F/,'\1'),
        title: "D&D 5e treasure table",
      }
    end

  end
end
