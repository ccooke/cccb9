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
        def self.new(match)
          if match[:reroll]
            Reroll.new(match)
          elsif match[:keep]
            Keep.new(match)
          elsif match[:drop]
            Drop.new(match)
          else
            raise Dice::Parser::NoModifier.new( "No such modifier: #{match[0]}" )
          end
        end

        class Reroll
          def initialize(match)
            if match[:conditional] != ""
              @condition_test = match[:conditional] == "=" ? :== : match[:conditional].to_sym
            else
              @condition_test = :==
            end
            @condition_num  = match[:condition_number].to_i
          end

          def reroll_with?(number)
            number.send( @condition_test, @condition_num )
          end
          
          def output(callbacks, parser)
          end
        end

        class Keep
          attr_reader :dropped

          def initialize(match)
            @keep_number = match[:keep_num].nil? ? 1 : match[:keep_num].to_i
            @keep_method = match[:keep_lowest] ? :max : :min
            @dropped = []
          end

          def fun(list)
            list.sort! { |x,y| (@keep_method==(:max)) ? x<=>y : y<=>x }
            newlist=list.shift(@keep_number)
          end
          
          def process(numbers)
            @dropped = []
            until numbers.count <= @keep_number
              remove = numbers.send(@keep_method)
              puts "Keep dropping #{remove}" if $DEBUG
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
        end

        class Drop
          attr_reader :dropped

          def initialize(match)
            @drop_number = match[:drop_num].nil? ? 1 : match[:drop_num].to_i
            @drop_method = match[:drop_lowest] ? :min : :max
            @dropped = []
          end

          def fun(list)
            list.sort! { |x,y| (@drop_method==(:min)) ? x<=>y : y<=>x}
            newlist=list.drop(@drop_number);
          end

          def process(numbers)
            @dropped = []
            dropped = 0
            until dropped == @drop_number or numbers.count == 0
              remove = numbers.send(@drop_method)
              puts "Dropping #{remove}" if $DEBUG
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
        end
      end

      attr_accessor :count, :size, :math_symbol
      def initialize( options = {} )
        @math_symbol = options[:math_symbol].to_sym
        @modifiers = options[:modifiers]
        @size = options[:size]
        @exploding = options[:exploding]
        @compounding = options[:compounding]
        @penetrating = options[:penetrating]
        @count = options[:count]
        @string = options[:string]
        @value = nil
        @rolls = Hash.new(0)
        @reroll_modifiers = @modifiers.select { |m| m.is_a? Modifier::Reroll }
        @fun_modifiers = @modifiers.select { |m| not (m.is_a? Modifier::Reroll) }
        if (1..@size).all? { |r| @reroll_modifiers.any? { |m| m.reroll_with? r } }
          raise Dice::Parser::Error.new( "Invalid reroll rules: No die roll is possible" )
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
        while rolls < count
          catch(:reroll) do
            @rolls[rolls] += 1
            puts "Roll #{rolls} of #{count}" if $DEBUG
            this_roll = roll_die
            number += this_roll
            puts "Rolled a #{this_roll}. Total is now #{number}" if $DEBUG

            if this_roll == @size
              if @penetrating
                puts "Reroll(penetrate)" if $DEBUG
                number -= 1
                throw :reroll
              elsif @compounding
                puts "Reroll(compound)" if $DEBUG
                throw :reroll          
              elsif @exploding 
                puts "Reroll(explode)" if $DEBUG
                count += 1
              end
            end
            
            if @modifiers.select { |m| m.is_a? Modifier::Reroll }.any? { |m| m.reroll_with? number }
              puts "Reroll #{number}" if $DEBUG
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
        @modifiers.each do |m|
          next unless m.respond_to? :process
          numbers = m.process(numbers)
        end
        numbers
      end

      def value
        @value.inject(:+)
      end

      def output( callbacks )
        output = [ @math_symbol ]
        if @value
          output << "["
          @value.each_with_index do |v,i|
            callbacks[:die].( v, @size, @rolls[i] )
            if callbacks.include? :die
              output << callbacks[:die].( self, v )
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
    end

    class FudgeDie < Die
      def initialize(match)
        super
        @modifiers = []
        @size = 6
      end
      
      def roll_die
        [ -1, -1, 0, 0, +1, +1 ][ SecureRandom.random_number(@size) ]
      end
    end

    attr_reader :terms, :density

    CONDITIONAL_BASE = %r{
      (?<conditional>     > | < | = |                                                     ){0}
      (?<nonzero>         [1-9]\d*                                                        ){0}
      (?<condition>       \g<conditional> (?<condition_number> \g<nonzero> )              ){0}
    }x

    MODIFIERS = %r{
      #{CONDITIONAL_BASE}
      (?<keep_highest>    kh | k                                                          ){0}
      (?<keep_lowest>     kl                                                              ){0}
      (?<drop_highest>    dh                                                              ){0}
      (?<drop_lowest>     dl | d                                                          ){0}
      (?<keep>            (\g<keep_lowest> | \g<keep_highest>) (?<keep_num> \g<nonzero> )?){0}
      (?<drop>            (\g<drop_highest> | \g<drop_lowest>) (?<drop_num> \g<nonzero> )?){0}
      (?<reroll>          r \g<condition>?                                                ){0}

      (?<die_modifier>    \g<drop> | \g<keep> | \g<reroll>                                ){0}
      (?<die_modifiers>   \g<die_modifier>*                                               ){0}

    }x

    MODIFIER_TERMS = %r{
      \G
      #{MODIFIERS}
      
      \g<die_modifier>
    }x

    EXPRESSION = %r{
      \G
      #{MODIFIERS}

      (?<penetrating>     !p                                                              ){0}
      (?<compounding>     !!                                                              ){0}
      (?<explode>         !                                                               ){0}
      (?<decoration>      \g<compounding> | \g<penetrating> | \g<explode>                 ){0}
  
      (?<fudge>           f                                                               ){0}
      (?<die_size>        \g<nonzero> | \g<fudge>                                         ){0}

      (?<mathlink>        \+ | -                                                          ){0}

      (?<die>    (?<count> \g<nonzero> ) d \g<die_size> \g<decoration>? \g<die_modifiers>?){0}

      (?<constant>        (?<constant_number> \g<nonzero> )                               ){0}

      (?<dice_string>
        \g<die>
        |
        \g<constant>
      ){0}

      \g<mathlink> \g<dice_string>
    }ix

    def initialize(string, options = {})
      @default = options[:default] || "+ 1d20"
      @default = @default.gsub(/\s+/, '')
      unless @default.start_with? '-' or @default.start_with? '+'
        @default = "+#{@default}"
      end
      expression = string.gsub /\s+/, ''
      @default.gsub! /\s+/, ''
      unless expression.start_with? '+'
        expression = '+' + expression
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
        p term 
        if term[:constant_number]
          Number.new term[:constant_number].to_i, term[:mathlink]
        elsif term[:die]
          options = {
            penetrating: !!term[:penetrating],
            compounding: !!term[:compounding],
            exploding: !!term[:explode],
            math_symbol: term[:mathlink].to_sym,
            string: term[:dice_string],
            
            count: term[:count].to_i,
          }
          if term[:fudge]
            FudgeDie.new options
          else
            options[:size] = term[:die_size].to_i
            options[:modifiers] = tokenize( MODIFIER_TERMS, term[:die_modifiers] ).map { |m| Die::Modifier.new( m ) }
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
  end
end
