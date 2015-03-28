require 'densities'
require 'securerandom'
require 'strscan'
require 'pp'

module Dice
  class Parser
    class Error < Exception; end
    class NoModifier < Exception; end

    class Term
      attr_accessor :density, :value

      def value
        @value || 0
      end
    end

    class Number < Term
      attr_accessor :number, :math_symbol
      def initialize( number, sign = :+ )
        @number = number.to_i
        @math_symbol = sign.to_sym
      end

      def density
        @density||=Density.new(@number)
      end
      
      def roll
        @value = @number
      end

      def sum(other)
        @value.send(@math_symbol, other )
      end

      def output(callbacks)
        "#{@math_symbol} #{callbacks[:number].(self,number)}"
      end
    end

    class Die < Term
      class Modifier

        def reset
        end

        def self.gen(match,size,modifiers)

          sub = nil
          subexpression = if match[:mod_subexpression]
            sub = Dice::Parser.new( match[:mod_subexpression] )
            sub.roll
            sub.value
          end

          if match[:reroll_once]
            obj = Reroll.new(match,size, subexpression, max_rerolls: 1 )
          elsif match[:reroll]
            obj = Reroll.new(match,size, subexpression, max_rerolls: 1000 )
          elsif match[:keep]
            obj = Keep.new(match,size, subexpression)
          elsif match[:drop]
            obj = Drop.new(match,size, subexpression)
          elsif match[:success] or match[:failure]
            pre = modifiers.find { |m| m.is_a? Test }
            if pre
              pre.add_match(match, size, subexpression)
              return pre
            else
              obj = Test.new(match, size, subexpression)
            end
          else
            raise Dice::Parser::NoModifier.new( "No such modifier: #{match[0]}" )
          end
          modifiers << obj
          obj.instance_variable_set :@subexpressions, sub
          obj
        end

        class Conditional < Modifier

          def reset
            @matches = 0
          end

          def init_condition(test, num, default = :==, subexpression = nil)
            self.reset
            if test.nil? or test == ""
              @condition_test = default
            else
              @condition_test = test == "=" ? default : test.to_sym
            end
            @condition_num = subexpression ? subexpression : num.to_i
          end

          def would_apply_with?(number)
            number.send(@condition_test, @condition_num)
          end

          def applies?(number)
            #p "TEST: ", @condition_test
            #p "NUM: ", @condision_num
            if would_apply_with?(number)
              @matches += 1
              true
            else
              false
            end
          end

          def condition_to_s
            "#{@condition_test == :== ? :"=" : @condition_test}#{@condition_num}"
          end

          def to_s
            "#{ self.class.name.split('::').last[0].downcase }#{condition_to_s}"
          end
        end

        def process(input)
          return input
        end
        alias_method :fun, :process

        def output(callbacks, parser)
        end

        class Test < Modifier
          attr_reader :unmodified

          def initialize(match,size, subexpression=nil)
            @tests = []
            add_match(match,size, subexpression)
          end

          def add_match(match,size, subexpression=nil)
            number = subexpression ? subexpression : match[:condition_number].to_i
            if match[:success]
              @tests << Success.new( match[:conditional], number || size, :>= )
            else
              @tests << Failure.new( match[:conditional], number || size )
            end
          end

          def process(input)
            #p input
            @unmodified = input
            @modified = input.map do |n|
              if @tests.any? { |i| i.fail? n }
                -1
              elsif @tests.any? { |i| i.success? n }
                @tests.count { |i| i.success? n }
              else
                0
              end
            end
          end

          def to_s
            @tests.map(&:to_s).join
          end

          def output(callbacks, parser)
            "(" + @modified.map.with_index { |die,i|
              #p "OUTPUT: ", [die, i, callbacks ]
              callbacks[:die].(parser, @unmodified[i]).to_s
            }.join(",") + ")"
          end
          
        end

        class Success < Conditional
          def initialize(cond, size, default = :==, subexpression = nil)
            init_condition( cond, size, default, subexpression )
          end

          def success?(number)
            #p self, number
            applies?(number)
          end

          def fail?(number)
            false
          end

          def to_s
            "s#{@condition_test}#{@condition_num}"
          end
        end

        class Failure < Success
          def success?(number)
            false
          end

          def fail?(number)
            #p self, number
            applies?(number)
          end

          def to_s
            "f#{@condition_test}#{@condition_num}"
          end
        end

        class Reroll < Conditional
          attr_reader :max_rerolls

          def initialize(match,size, subexpression, max_rerolls: 1000 )
            @max_rerolls = max_rerolls
            number = subexpression ? subexpression : match[:condition_number].to_i
            #p match
            init_condition( match[:conditional], number || 1 )
          end

          def applies?(number)
            if @matches > @max_rerolls
              false
            else
              super
            end
          end

          def reroll_with?(number)
            would_apply_with? number
          end
          
          def output(callbacks, parser)
          end

          def to_s
            "r#{if @max_rerolls == 1 then 'o' end}#{@condition_test}#{@condition_num}"
          end
        end

        class Fudge < Modifier
          def process(input)
            input.map { |i| i = (i-1) / 2 - 1 }
          end
          
          def output(callbacks, parser)
          end

          def to_s
            ""
          end
        end

        class Keep < Modifier
          attr_reader :dropped

          def initialize(match,size, subexpression)
            number = subexpression ? subexpression : match[:keep_num].to_i
            @keep_number = match[:keep_num].nil? ? 1 : number
            @keep_method = match[:keep_lowest] ? :max : :min
            @dropped = []
          end

          def process(input)
            @dropped = []
            numbers = input.dup
            until numbers.count <= @keep_number
              remove = numbers.send(@keep_method)
              #puts "Keep dropping #{remove}" if $DEBUG
              @dropped << remove
              numbers.delete_at( numbers.index( remove ) ) 
            end
            numbers
          end
          
          def output(callbacks, parser)
            output = @dropped.map do |die|
              callbacks[:die].(parser, die)
            end
            "(unkept: #{output.join(", ")})"
          end
          
          def to_s
            "k#{@keep_method == :max ? 'l' : 'h' }#{@keep_number}"
          end
        end

        class Drop < Modifier
          attr_reader :dropped

          def initialize(match,size, subexpression)
            number = subexpression ? subexpression : match[:drop_num].to_i
            @drop_number = match[:drop_num].nil? ? 1 : number
            @drop_method = match[:drop_lowest] ? :min : :max
            @dropped = []
          end

          def process(input)
            @dropped = []
            dropped = 0
            numbers = input.dup
            until dropped == @drop_number or numbers.count == 0
              remove = numbers.send(@drop_method)
              #puts "Dropping #{remove}" if $DEBUG
              @dropped << remove
              dropped += 1
              numbers.delete_at( numbers.index( remove ) )
            end
            numbers
          end

          def output(callbacks, parser)
            output = @dropped.map do |die|
              callbacks[:die].(parser,die)
            end
            "(dropped #{output.join(", ")})"
          end

          def to_s
            "d#{@drop_method == :max ? 'h' : 'l'}#{@drop_number}"
          end
        end
      end

      attr_accessor :count, :size, :math_symbol
      def initialize( options = {} )
        @math_symbol = options[:math_symbol].to_sym
        @modifiers = options[:modifiers]
        @size = options[:size]
        if @size > 9999 
          raise Dice::Parser::Error.new( "Invalid die: No more than 10,000 sides" )
        end
        @exploding = options[:exploding]
        @compounding = options[:compounding]
        @penetrating = options[:penetrating]
        @decorator_condition = options[:decorator_condition] == "=" ? :== : options[:decorator_condition].to_sym
        @decorator_number = options[:decorator_number] || @size
        @count = options[:count] > 100 ? 100 : options[:count]
        @string = options[:string]
        @value = nil
        @rolls = Hash.new(0)
        @reroll_modifiers = @modifiers.select { |m| m.is_a? Modifier::Reroll }
        @fun_modifiers = @modifiers.select { |m| not (m.is_a? Modifier::Reroll) }
        safe = (1..@size).select { |r| @reroll_modifiers.none? { |m| m.reroll_with? r } }
        if safe.empty?
          raise Dice::Parser::Error.new( "Invalid reroll rules: No die roll is possible" )
        end
        if safe.all? { |n| explode? n }
          #p self
          raise Dice::Parser::Error.new( "Pathological expression: Reroll and Explode rules overlap" )
        end
      end

      def explode?(number)
        if @penetrating or @exploding or @compounding
          #p "explode? #{number}: ", [ @decorator_condition, @decorator_number ]
          number.send(@decorator_condition, @decorator_number)
        else 
          false
        end
      end

      def decorator_condition
        if @decorator_condition == :>= and @decorator_number == @size
          ""
        else
          "#{@decorator_condition}#{@decorator_number}"
        end
      end

      def decorators
        if @penetrating or @exploding or @compounding
          case
          when @penetrating
            '!p'
          when @compounding
            '!!'
          when @exploding
            '!'
          end + decorator_condition
        else
          ""
        end
      end

      def density
        if (@density.is_a? Density)
          return @density
        end
        rerolls=(1..@size).to_a.select { |r| @reroll_modifiers.any? { |m| m.reroll_with? r } }
        if(@compounding)
          temp=CompoundDieDensity.new(@size,rerolls)
          @density=ModifiedDieDensity.new(temp,@count,@fun_modifiers)
        elsif(@penetrating)
          temp=PenetratingDieDensity.new(@size,rerolls)
          @density=ModifiedDieDensity.new(temp,@count,@fun_modifiers)
        # This is a rather special case....
        elsif(@exploding)
          temp=DieDensity.new(@size,(rerolls+[@size]).uniq)
          exploding_count=ExplodingDieNumberDensity.new(@size,rerolls,@count)

          if (rerolls.include? @size)
            @density=ModifiedDieDensity.new(temp,exploding_count,@fun_modifiers)
          else
            @density=ExplodingDieDensity.new(temp,@size,@count,exploding_count,@fun_modifiers)
          end
        else
          temp=DieDensity.new(@size,rerolls)
          @density=ModifiedDieDensity.new(temp,@count,@fun_modifiers)
        end
        @density
      end

      def roll_die
        SecureRandom.random_number( @size ) + 1
      end

      def roll
        temp = []
        count = @count
        rolls = 0
        number = 0
        @modifiers.map(&:reset)
        while rolls < count
          catch(:reroll) do
            @rolls[rolls] += 1
            #puts "Roll #{rolls} of #{count}" if $DEBUG
            this_roll = roll_die
            number += this_roll
            #puts "Rolled a #{this_roll}. Total is now #{number}" if $DEBUG

            if explode? this_roll
              if @penetrating
                #puts "Reroll(penetrate)" if $DEBUG
                number -= 1
                throw :reroll
              elsif @compounding
                #puts "Reroll(compound)" if $DEBUG
                throw :reroll          
              elsif @exploding 
                #puts "Reroll(explode)" if $DEBUG
                count += 1 if count < 100
              end
            end
            
            if @modifiers.select { |m| m.is_a? Modifier::Reroll }.any? { |m| m.applies? number }
              number = 0
              throw :reroll
            end

            temp << number
            rolls += 1
            number = 0
          end
        end
        @value = process_modifiers( temp )
      end

      def process_modifiers(numbers)
        #p numbers
        @modifiers.each do |m|
          next unless m.respond_to? :process
          #p m
          numbers = m.process(numbers)
          #p numbers
        end
        numbers
      end

      def modifiers
        @modifiers.map(&:to_s).join(" ")
      end

      def value
        @value.inject(:+)
      end

      def output( callbacks, callback_to_use = :die )
        output = [ to_s ]
        if @value
          output << "\\["
          @value.each_with_index do |v,i|
            if callbacks.include? callback_to_use
              output << callbacks[callback_to_use].( self, v )
            else
              output << v
            end
          end
          output << "]"
          if @modifiers.any? { |m| m.respond_to? :process }
            output << @modifiers.map { |m| m.output( callbacks, self ) }
          end
        end
        output
      end

      def to_s
        "#{ @math_symbol }#{@count}d#{size}#{decorators}#{modifiers}"
      end

    end

    class FudgeDie < Die
      def initialize(options = {})
        options[:size] = 6
        options[:modifiers] = [ Die::Modifier::Fudge.new ]
        super
      end
      
      def output( callbacks, callback_to_use = :fudge )
        super( callbacks, callback_to_use )
      end

      def to_s
        "#{ @math_symbol }#{@count}dF#{decorators}#{modifiers}"
      end
    end

    attr_reader :terms, :density

    EXPRESSION_BASE = %r{
      (?<conditional>     > | < | = |                                                     ){0}
      (?<paren_expression> \( (?: (?> [^()]+ ) | \g<paren_expression> )* \)               ){0}
      (?<mod_nonzero>     [0-9]\d* | (?<mod_subexpression> \g<paren_expression> )         ){0}
      (?<die_nonzero>     [0-9]\d* | (?<die_subexpression> \g<paren_expression> )         ){0}
      (?<dc_nonzero>      [0-9]\d* | (?<dc_subexpression> \g<paren_expression> )          ){0}
      (?<con_nonzero>      [0-9]\d* | (?<con_subexpression> \g<paren_expression> )          ){0}
      (?<condition>       \g<conditional> \s* (?<condition_number> \g<mod_nonzero> )      ){0}
      (?<keep_highest>    kh | k                                                          ){0}
      (?<keep_lowest>     kl                                                              ){0}
      (?<drop_highest>    dh                                                              ){0}
      (?<drop_lowest>     dl | d                                                          ){0}
      (?<keep>            (\g<keep_lowest> | \g<keep_highest>) (?<keep_num> \g<mod_nonzero> )?){0}
      (?<drop>            (\g<drop_highest> | \g<drop_lowest>) (?<drop_num> \g<mod_nonzero> )?){0}
      (?<failure>         f \s* \g<condition>?                                            ){0}
      (?<success>         s \s* \g<condition>?                                            ){0}
      (?<wolf>            w \s* \g<condition>                                             ){0}
      (?<reroll>          (?: (?<reroll_once> ro ) | r(?!o) ) \s* \g<condition>?               ){0}

      (?<die_modifier> \g<drop> | \g<keep> | \g<reroll> | \g<success> | \g<failure> | \g<wolf> ){0}
      (?<die_modifiers>   \g<die_modifier>*                                               ){0}
      (?<penetrating>     !p                                                              ){0}
      (?<compounding>     !!                                                              ){0}
      (?<explode>         !                                                               ){0}
      (?<dconditional>    \g<conditional>                                                 ){0}
      (?<dcondition>      \g<dconditional> \s* (?<dcondition_number> \g<dc_nonzero> )     ){0}
      (?<decoration>      \g<compounding> | \g<penetrating> | \g<explode> \s* \g<dcondition>?     ){0}
  
      (?<fudge>           f                                                               ){0}
      (?<die_size>        \g<die_nonzero> | \g<fudge>                                     ){0}

      (?<mathlink>        \+ | -                                                          ){0}

      (?<die>    (?<count> \g<die_nonzero> )? \s* d \s* \g<die_size> \s* \g<decoration>? \s* \g<die_modifiers>?){0}

      (?<constant>        (?<constant_number> \g<con_nonzero> )                           ){0}

      (?<dice_string>
        \g<die>
        |
        \g<constant>
      ){0}

      (?<dice_expression> \g<dice_string> (?: \s* \g<mathlink> \s* \g<dice_string> \s* )* ){0}
    }ix

    PAREN_EXPRESSION = %r{
      #{EXPRESSION_BASE}
      \s* \g<mathlink> \s* \g<paren_expression>
    }ix

    EXPRESSION = %r{
      \G
      #{EXPRESSION_BASE}
      \s* \g<mathlink> \s* \g<dice_string> \s*
    }ix

    MODIFIER_TERMS = %r{
      \G
      #{EXPRESSION_BASE}
      \s* \g<die_modifier> \s*
    }ix

    def initialize(string, options = {})
      @default = options[:default] || "+ 1d20"
      @default = @default.gsub(/\s+/, '')
      @subexpressions = []
      unless @default.start_with? '-' or @default.start_with? '+'
        @default = "+#{@default}"
      end
      expression = string.gsub /\s+/, ''
      @default.gsub! /\s+/, ''
      unless expression.start_with? '+' or expression.start_with? '-'
        expression = '+' + expression
      end
      #p expression
      if PAREN_EXPRESSION.match( expression )
        expression.gsub!( /^\s*([-+])\s*\(\s*(.*?)\s*\)\s*$/, "\\1\\2" )
      end
      @string = expression
      @terms = parse
    end

    def tokenize(regex, string)
      index = 0
      items = []
      while match = string.match( regex, index )
        items << match
        index = match.end(0)
      end
      unless index == string.length
        raise Dice::Parser::Error.new( "Parsing of #{string} failed at character #{index}: #{string[index,string.length]}" )
      end
      items
    end

    def tokenize_dice_expression
      items = tokenize(EXPRESSION, @string)
      if items.none? { |i| i[:die] }
        items += tokenize( EXPRESSION, @default )
      end
      items.compact
    end

    def parse
      tokenize_dice_expression.map do |term|
        #p term 
        subexpression = if term[:die_subexpression]
          sub = Dice::Parser.new(term[:die_subexpression])
          @subexpressions << sub
          sub.roll
          sub.value
        else
          nil
        end

        if term[:constant_number]
          constant = subexpression ? subexpression : term[:constant_number].to_i
          Number.new constant, term[:mathlink]
        elsif term[:die]
          die_size = subexpression ? subexpression : term[:die_size].to_i
          condition_subexpression = if term[:dc_subexpression]
            sub = Dice::Parser.new(term[:dc_subexpression])
            @subexpressions << sub
            sub.roll
            sub.value
          end
          count_subexpression = if term[:con_subexpression]
            sub = Dice::Parser.new(term[:con_subexpression])
            @subexpressions << sub
            sub.roll
            #p "Found a constant subexpression: ", sub
            sub.value
          end
          options = {
            penetrating: !!term[:penetrating],
            compounding: !!term[:compounding],
            exploding: !!term[:explode],
            decorator_condition: term[:dconditional] || '>=',
            decorator_number: ( condition_subexpression || term[:dcondition_number] || die_size ).to_i,
            math_symbol: term[:mathlink].to_sym,
            string: term[:dice_string],
            
            count: (count_subexpression || term[:count] || 1).to_i,
          }
          if term[:fudge]
            FudgeDie.new options
          else
            options[:size] = die_size
            options[:modifiers] = []
            modifiers = term[:die_modifiers].gsub(/w/, 'f=1s=10s')
            tokenize( MODIFIER_TERMS, modifiers ).map { |m| Die::Modifier.gen( m, options[:size], options[:modifiers] ) }
            Die.new options
          end
        end
      end
    end

    def roll
      @terms.map(&:roll)
    end

    def value
      @terms.inject(0) do |i,t|
        i.send(t.math_symbol, t.value)
      end
    end

    def density
      @density||=@terms.inject(Density.new) { |i,t| i.send(t.math_symbol,t.density) }      
    end
    
    def expect
      @density.expect
    end

    def output( callbacks = {}, default_proc = Proc.new { |o,v| v } )
      callbacks.default = default_proc
      @terms.map { |t|
        t.output( callbacks )
      }.flatten.compact.join(" ")
    end

    def to_s
      @terms.map(&:to_s).join
    end

    def average
      probabilities = self.density
      max_probability = probabilities.map(&:last).max
      modes = probabilities.select { |n,p| p == max_probability }.map(&:first)
      average = modes.inject(:+) / modes.count.to_f
    end
  end
end
