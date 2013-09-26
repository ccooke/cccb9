require 'facets/array/combination'
require 'forwardable'
 

# DENSITY CLASS
# =============
#

class Density
  include Enumerable
  extend Forwardable

  attr_accessor :uniform, :fail, :exact
  def_delegators :@d, :each, :[], :[]=, :inspect, :delete
 
  def initialize(num=0)
    @d=Hash.new(Rational(0))
    @d[num]=Rational(1)
    @uniform=true
    @exact=true
    @fail=false
  end
  
  def roll
    if (@probability_interval.nil?)
      @probability_interval=@d.to_a
      i=0
      @probability_interval.map! { |k,v| [k,i=(v+i)] }
    end
    r=rand()
    if (Array.respond_to?(:bsearch))
      index=@probability_interval.bsearch { |k| k[1]>r }
    else
      index=@probability_interval.index { |k| k[1]>r }
    end
    return @probability_interval[index][0]
  end
  
  # addition of INDEPENDENT densities
  def +(y)
    z=Density.new
    z.delete(0)
    z.uniform=@uniform
    z.exact=@exact
    z.fail=@fail
    
    if (y.is_a?Density)
      if (y.fail)
        z.fail=true
      end
      if (not y.exact)
        z.exact=false
      end
      if (y.to_a.size>1 and @d.to_a.size>1)
        z.uniform=false
      end
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
  # TODO (if we need it): Fix the issues if it is a density and not a numeric
  def *(y)
    z=Density.new
    z.delete(0)
    z.uniform=@uniform
    z.exact=@exact
    z.fail=@fail

    if (y.is_a?Density)
      if (y.fail)
        z.fail=true
      end
      if (y.exact)
        z.exact=false
      end
      if (y.to_a.size>1 and @d.to_a.size>1)
        z.uniform=false
      end
      max=(@d.keys + y.keys).collect(:abs).max
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
  def -(y)
    return self+(y*(-1))
  end

  # returns the probability that X<n, X>n, X<=n, X>=n
  def <(n)
    entries=@d.select { |k,v| k<n };
    (entries.empty?) ? 0 : entries.values.inject(:+)
  end
  def >(n)
    entries=@d.select { |k,v| k>n };
    (entries.empty?) ? 0 : entries.values.inject(:+)
  end
  def <=(n)
    entries=@d.select { |k,v| k<=n };
    (entries.empty?) ? 0 : entries.values.inject(:+)
  end
  def >=(n)
    entries=@d.select { |k,v| k>=n };
    (entries.empty?) ? 0 : entries.values.inject(:+)
  end

  # returns the expecctation value
  def expect
    @d.inject(0) { |i,(k,v)| i+k*v }
  end
end



# density of a die roll with rerolls
class DieDensity < Density
  def initialize(max,rerolls=[])
    super(0)
    if (rerolls.size>0)
      @uniform=false
    end
    @d.delete(0)
    n=max-rerolls.size
    for k in (1..max).reject{ |n| rerolls.include?n } do
      @d[k]=Rational(1,n)
    end
  end
end
  
# density of a die roll with compound decorator and rerolls
class CompoundDieDensity < Density
  def initialize(max,rerolls=[],maxcompound=10)
    super(0)
    @uniform=false
    @d.delete(0)
    basepart=getBasePart(max,rerolls)
    n=max - rerolls.reject{ |n| n==max }.size         
    i=0
    while (i<=maxcompound) do
      basepart.each do |k,v|
        @d[k+max*i]=Rational(v,n**i)
      end
      i+=1
    end
    #The last max value has a different probability
    @d[max*i]=Rational(1,n**i)
  end
  
  # HELPER FUNCTION: returns the density of a die with rerolls
  # but with a removed max value, so this DOESN'T give a density
  def getBasePart(max,rerolls=[])
    z=Density.new
    z.delete(0)
    z.fail=true
    z.exact=false
    z.uniform=false
    n=max - rerolls.reject{ |n| n==max }.size
    for k in (1..(max-1)).reject{ |n| rerolls.include?n } do
      z[k]=Rational(1,n)
    end
    return z
  end
end

# density of a die roll with penetrating decorator and rerolls
class PenetratingDieDensity < Density
  def initialize(max,rerolls=[],maxpenetrate=10)
    super(0)
    @uniform=false
    @d.delete(0)
    basepart=getBasePart(max,rerolls)
    n=max - rerolls.reject{ |n| n==max }.size         
  
    # a (very) special case (namely if reroll contains max)
    if (rerolls.include?max)
      basepart.each do |k,v|
        @d[k]=v
      end
      basepart.each do |k,v|
        if (k+max-1 != max)
          @d[k+max-1]=Rational(v,n-1)
        end
      end
      i=2
      while (i<=maxpenetrate) do
        basepart.each do |k,v|
          @d[k+(max-1)*i]=Rational(v,(n-1)*n**i)
        end
        i+=1
      end
    #normal case
    else 
      i=0
      while (i<=maxpenetrate) do
        basepart.each do |k,v|
          @d[k+(max-1)*i]=Rational(v,n**i)
        end
        i+=1
      end
    end
    #The last max value has a different probability
    @d[(max-1)*i+1]=Rational(1,n**i)
  end

  # HELPER FUNCTION: returns the density of a die with rerolls
  # but with a removed max value, so this DOESN'T give a density
  def getBasePart(max,rerolls=[])
    z=Density.new
    z.delete(0)
    z.exact=false
    z.fail=true
    z.uniform=false
    n=max - rerolls.reject{ |n| n==max }.size
    for k in (1..(max-1)).reject{ |n| rerolls.include?n } do
      z[k]=Rational(1,n)
    end
    return z
  end
end

class ExplodingDieDensity < Density
  # TODO
  def initialize(max,rerolls=[])
    super(0)
    @fail=true
    @exact=false
  end
end

# density of a modified die roll:
# n identical dices are rolled and then modified according to some function (modifier)
# if no modifier is present then the dice results are simply summed
class ModifiedDieDensity < Density
  def initialize(density,number,modifiers=[])
    # TODO: find a good number
    num=10000
    (modifiers.is_a? Array) ? mods=modifiers : mods=[modifiers]
    if (number.zero?)
      super(0)
    elsif (modifiers==[])
      @d=([density]*number.abs).inject(:+)
    elsif (density.to_a.size**number.abs > num*10)
      super(0)
      @exact=false
      @uniform=false
      @d.delete(0)
      i=0
      while (i<num)
        keys=Array.new(number.abs).map! { |i| density.roll }
        newkeys=mods.inject(keys) { |i,m| m.fun(i) }
        if newkeys.size==0
          @d[0]+=values.inject(:*)
        else
          @d[newkeys.inject(:+)]+=Rational(1,num)
        end
        i+=1
      end
    else
      super(0)
      @uniform=false
      @d.delete(0)
      permutations=(density.to_a).repeated_permutation(number.abs)
      permutations.each do |comb|
        values=comb.map {|a,b| b }
        keys=comb.map {|a,b| a }
        newkeys=mods.inject(keys) { |i,m| m.fun(i) }
        if newkeys.size==0
          @d[0]+=values.inject(:*)
        else
          @d[newkeys.inject(:+)]+=values.inject(:*)
        end
      end
    end
    if (number<0)
      @d*=-1
    end
  end
end

