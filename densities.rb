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
    (n.is_a?Numeric) ? hash.select { |k,v| k<n }.values.inject(:+) : nil
  end
  def >(n)
    (n.is_a?Numeric) ? hash.select { |k,v| k>n }.values.inject(:+) : nil
  end
  def <=(n)
    (n.is_a?Numeric) ? hash.select { |k,v| k<=n }.values.inject(:+) : nil
  end
  def >=(n)
    (n.is_a?Numeric) ? hash.select { |k,v| k>=n }.values.inject(:+) : nil
  end
end














# EVERYTHING RELATED TO DICE DENSITIES
# ====================================
#

# returns the density of a die with rerolls
def getDie(max,rerolls=[])
  z=Density.new
  z[0]=0
  n=max-rerolls.size
  for k in (1..max).reject{ |n| rerolls.include?n } do
    z[k]=Rational(1,n)
  end
  return z
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
  return z
end

# returns the density of a die roll with compound decorator and rerolls
def getCompoundDie(max,rerolls=[],maxcompound=100)
  z=Density.new
  d=getBasePart(max,rerolls)
  n=max - rerolls.reject{ |n| n==max }.size         
  i=0
  while (i<maxcompound) do
    d.each do |k,v|
      z[k+max*i]=Rational(v,n**(i+1))
    end
    i+=1
  end
  return z
end

# returns the density of a die roll with penetrating decorator and rerolls
def getPenetratingDie(max,rerolls=[],maxpenetrate=100)
  z=Density.new
  d=getBasePart(max,rerolls)
  n=max - rerolls.reject{ |n| n==max }.size         

  # a (very) special case (if reroll contains max)
  if (rerolls.include?max)
    d.each do |k,v|
      z[k]=Rational(v,n)
    end
    d.each do |k,v|
      if (k+max-1 != max)
        z[k+(max-1)]=Rational(v,(n-1)*n)
      end
    end
    i=2
    while (i<maxpenetrate) do
      d.each do |k,v|
        z[k+(max-1)*i]=Rational(v,(n-1)*n**i)
      end
      i+=1
    end
  #normale case
  else 
    i=0
    while (i<maxpenetrate) do
      d.each do |k,v|
        z[k+(max-1)*i]=Rational(v,n**(i+1))
      end
      i+=1
    end
  end
  return z
end

def getModifierDensity(modifier,density,number)
  z=Density.new
  combination=(density.to_a).repeated_combination(number)
  combination.each do |comb|
    values=comb.map {|a,b| b }
    keys=comb.map {|a,b| a }
    z[modifier.apply(keys)]+=values.inject(:*)
  end
  return z
end

class StandardModifier
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

d=Density.new(3)

density = Array.new(5,getDie(3,[2])).inject(:+)
pp density
getModifierDensity(StandardModifier.new,density,3)
                                 


#puts convList(Array.new(5,getDie(20,[1,2])))
#puts getPenetratingDie(10,[1,4,20],10)
  
