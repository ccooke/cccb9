#!/usr/bin/ruby

load './dice.rb'
require 'facets/array/combination'
require 'forwardable'
 

# DENSITY CLASS
# =============
#

class Density
  include Enumerable
  extend Forwardable

  def_delegators :@d, :each, :[], :[]=, :inspect
  
 
  def initialize(num=0)
    @d=Hash.new(Rational(0))
    @d[num]=Rational(1)
  end
  
  # addition of INDEPENDENT densities
  def +(y)
    z=Density.new
    z[0]=Rational(0)
    if (y.is_a?Density)
      @d.each do |xkey,xvalue|
        y.each do |ykey,yvalue|
          z[xkey+ykey]+=xvalue*yvalue
        end
      end
    elsif (y.is_a?Numeric)
      @d.each do |xkey,xvalue|
        z[xkey+y]+=xvalue
      end    
    else
      #TODO
    end
    return z
  end

  # multiplication of INDEPENDENT densities
  def *(y)
    z=Density.new
    z[0]=Rational(0)
    max=(@d.keys + y.keys).collect(:abs).max
    if (y.is_a?Density)
      for n in (-max..max) do 
        ((-n..n).collect { |d| [d,n/d] if ((n/d) * d) == n}.compact).each do |d,e|
          z[n]+=Rational(@d[d]*y[e],abs(d))
        end
      end
    elsif (y.is_a?Numeric)
      @d.each do |k,v|
        z[k*y]=v
      end
    else
      #TODO
    end
    return z
  end

  def -()
    return self*(-1)
  end

  # returns the probability that X<n, X>n, X<=n, X>=n
  def <(n)
    (n.is_a?Numeric) ? @d.select { |k,v| k<n }.values.inject(:+) : nil
  end
  def >(n)
    (n.is_a?Numeric) ? @d.select { |k,v| k>n }.values.inject(:+) : nil
  end
  def <=(n)
    (n.is_a?Numeric) ? @d.select { |k,v| k<=n }.values.inject(:+) : nil
  end
  def >=(n)
    (n.is_a?Numeric) ? @d.select { |k,v| k>=n }.values.inject(:+) : nil
  end
end



# density of a die roll with rerolls
class DieDensity < Density
  def initialize(max,rerolls=[])
    super(0)
    @d[0]=0
    n=max-rerolls.size
    for k in (1..max).reject{ |n| rerolls.include?n } do
      @d[k]=Rational(1,n)
    end
  end
end
  
# density of a die roll with compound decorator and rerolls
class CompoundDieDensity < Density
  def initialize(max,rerolls=[],maxcompound=100)
    super(0)
    @d[0]=0
    basepart=getBasePart(max,rerolls)
    n=max - rerolls.reject{ |n| n==max }.size         
    i=0
    while (i<maxcompound) do
      basepart.each do |k,v|
        @d[k+max*i]=Rational(v,n**(i+1))
      end
      i+=1
    end
  end
  
  # HELPER FUNCTION: returns the density of a die with rerolls
  # but with a removed max value, so this DOESN'T give a density
  def getBasePart(max,rerolls=[])
    z=Density.new
    z[0]=0
    n=max - rerolls.reject{ |n| n==max }.size
    for k in (1..(max-1)).reject{ |n| rerolls.include?n } do
      z[k]=Rational(1,n)
    end
  end
end

# density of a die roll with penetrating decorator and rerolls
class PenetratingDieDensity < Density
  def initialize(max,rerolls=[],maxpenetrate=100)
    super(0)
    @d[0]=0
    basepart=getBasePart(max,rerolls)
    n=max - rerolls.reject{ |n| n==max }.size         
  
    # a (very) special case (namely if reroll contains max)
    if (rerolls.include?max)
      basepart.each do |k,v|
        @d[k]=Rational(v,n)
      end
      basepart.each do |k,v|
        if (k+max-1 != max)
          @d[k+(max-1)]=Rational(v,(n-1)*n)
        end
      end
      i=2
      while (i<maxpenetrate) do
        basepart.each do |k,v|
          @d[k+(max-1)*i]=Rational(v,(n-1)*n**i)
        end
        i+=1
      end
    #normal case
    else 
      i=0
      while (i<maxpenetrate) do
        basepart.each do |k,v|
          @d[k+(max-1)*i]=Rational(v,n**(i+1))
        end
        i+=1
      end
    end
  end

  # HELPER FUNCTION: returns the density of a die with rerolls
  # but with a removed max value, so this DOESN'T give a density
  def getBasePart(max,rerolls=[])
    z=Density.new
    z[0]=0
    n=max - rerolls.reject{ |n| n==max }.size
    for k in (1..(max-1)).reject{ |n| rerolls.include?n } do
      z[k]=Rational(1,n)
    end
  end
end

class ExplodingDieDensity < Density
  # TODO
end

# density of a modified die roll:
# n identical dices are rolled and then modified according to some function (modifier)
# if no modifier is present then the dice results are simply summed
class ModifiedDieDensity < Density
  def initialize(density,number,modifier=nil)
    if (number.zero?)
      super()
    elsif (modifier.is_a?Modifier)
      super()
      @d[0]=0
      combination=(density.to_a).repeated_combination(number.abs)
      combination.each do |comb|
        values=comb.map {|a,b| b }
        keys=comb.map {|a,b| a }
        @d[modifier.apply(keys)]+=values.inject(:*)
      end
      (number<0) ? @d*=-1 : nil
    else
      @d=([density]*number.abs).inject(:+)
      (number<0) ? @d*=-1 : nil
    end
  end
end

class Modifier
end
class StandardModifier < Modifier
  def apply(lis)
    lis.inject(:+)
  end
end










# TESTS
# =====
#

t = Dice::Parser.new ARGV[0].dup
t.terms.each do |term|
  pp term.density
end

diedensity = ([DieDensity.new(3,[2])]*5).inject(:+)
pp (diedensity<=10)
moddensity = ModifiedDieDensity.new(diedensity,3,StandardModifier.new)
pp moddensity<=40 
  
