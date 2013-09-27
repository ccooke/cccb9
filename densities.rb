require 'forwardable'
 

# DENSITY CLASS
# =============
#

class Density
  include Enumerable
  extend Forwardable

  attr_accessor :uniform, :fail, :exact, :d
  def_delegators :@d, :each, :[], :[]=, :inspect, :delete, :values
 
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
      if ((not y.uniform) or (y.to_a.size>1 and self.to_a.size>1))
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
    end
    return z
  end

  # multiplication of INDEPENDENT densities
  def *(y)
    z=Density.new
    z.delete(0)
    z.uniform=@uniform
    z.exact=@exact
    z.fail=@fail

    # TODO: check if this is working correctly
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
    end
    return z
  end

  def -()
    return self*(-1)
  end
  def -(y)
    return self+(y*(-1))
  end

  # reduce the probability of all entries matching <condition> to zero, adjust the rest accordingly
  def delete_if
    remove_values=@d.select {|item| yield item }.values
    remove_prob=(remove_values==[]) ? 0 : remove_values.inject(:+)
    if (remove_prob<1)
      @d.delete_if {|item| yield item }
      @d=(self.mult(Rational(1,1-remove_prob))).d
    else
      # TODO
    end
  end

  # keep only the entries matching <condition>, adjust their probability accordingly
  def keep_if
    keep_values=(@d.select {|item| yield item}).values
    keep_prob=(keep_values==[]) ? 0 : keep_values.inject(:+)
    if (keep_prob>0)
      @d.keep_if {|item| yield item}
      @d=(self.mult(Rational(1,keep_prob))).d
    else
      # TODO
    end
  end

  # assumes that y is a Density and does pointwise addition. The result is no longer a density!!
  def add(y)
    z=Density.new
    z.delete(0)
    z.uniform=false
    z.exact=false
    z.fail=true

    z.d=@d.merge(y.d){|key, oldval, newval| newval + oldval}
    return z
  end
  # Assumes that y is a Numeric and does pointwise multiplication. The result is no longer a density!!
  def mult(y)
    z=Density.new
    z.delete(0)
    z.uniform=false
    z.exact=false
    z.fail=true

    @d.each { |k,v| z[k]=v*y }
    return z
  end
  def sub(y)
    return self.add(y.mult(-1))
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

  # returns the variance
  def variance
    mu=expect()
    @d.inject(Rational(-mu*mu)) { |i,(k,v)| i+k*k*v }
  end
  
  # returns the standard deviation
  def stdev
    Math.sqrt(variance)
  end
  
  # density plot
  def plot(width=50)
    max=@d.values.max
    minperc=max*0.5/width*0.95

    plotvar=sprintf("\n")
    @d.select {|k,v| v>=minperc}.each do |k,v|
      plotvar+=sprintf("%5d | ",k)
      barnum=(v*width*1.0/max).round
      for k in (1..barnum) do
        plotvar+="|"
      end
      plotvar+="\n"
    end
    plotvar
  end
end



# density of a die roll with rerolls
class DieDensity < Density
  def initialize(max,rerolls=[])
    super()
    @uniform=false
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
    super()
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
    super()
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

# density for the _number_ of rolled exploding dices (starting with count), with rerolls
# and up to maxexplode explosions
class ExplodingDieNumberDensity < Density
  def initialize(max,rerolls=[],count=1,maxexplode=10)
    super()
    z=Density.new
    z.delete(0)
    
    if (rerolls.include?max)
      n=max - rerolls.size + 1
      z[1]=Rational(n-1,n)
      for k in (2..maxexplode) do
        for r in (1..(k-1)) do
          z[k]+=Rational(z[r]*z[k-r],n)
        end
      end
      z[maxexplode+1]=1-z.values.inject(:+)
    else
      n=max - rerolls.size
      for k in (1..maxexplode) do
        z[k]=Rational(n-1,n**k)
      end
      z[maxexplode+1]=Rational(1,n**(e-1))
    end

    @d=(([z]*count).inject(:+)).d
    @uniform=false
    # if we only limit the explosions of individual dices don't do the following command:
    delete_if { |k,v| k > maxexplode + 1}
  end
end

# density of a modified die roll:
# "number" identical dices are rolled and then modified according to some function (modifier)
# if no "modifier" is present then the dice results are simply summed
# if "number" is a Density then each case is considered with the appropriate probability
class ModifiedDieDensity < Density
  def initialize(density,number,modifiers=[])
    # TODO: find a good number and a good factor (monte carlo step vs. exact step)
    super()
    num=10000
    factor=10

    (modifiers.is_a? Array) ? mods=modifiers : mods=[modifiers]

    # if we have a distribution of numbers given by a density
    # (potentially also BRUTE FORCE)
    if (number.is_a? Density)
      initial_density=Density.new;
      initial_density.delete(0);
      z=number.inject(initial_density) do |i,(n,p)|
        temp_d=ModifiedDieDensity.new(density,n,modifiers)
        temp_fail=temp_d.fail or i.fail
        temp_exact=temp_d.exact and i.exact
        i=i.add(temp_d.mult(p))
        i.fail=temp_fail
        i.exact=temp_exact
        i
      end
      
      @d=z.d
      @fail=z.fail
      @exact=z.exact
      @uniform=false
    # if we have a fixed number
    else 
      if (number.zero?)
      elsif (modifiers==[])
        @d=(([density]*number).inject(:+)).d
        if (number>1)
          @uniform=false
        end
      # This is (the only place) where we decide whether we do APPROXIMATIONS or precise calculations
      # Monte-Carlo approximation
      elsif (stepnum(density.to_a.size,number) > num*factor)
        @exact=false
        @uniform=false
        @d.delete(0)
        i=0
        while (i<num)
          keys=Array.new(number).map! { |i| density.roll }
          newkeys=mods.inject(keys) { |i,m| m.fun(i) }
          if newkeys.size==0
            @d[0]+=values.inject(:*)
          else
            @d[newkeys.inject(:+)]+=Rational(1,num)
          end
          i+=1
        end
      # BRUTE FORCE
      else
        @uniform=false
        @d.delete(0)
        (density.to_a).repeated_combination(number).each do |comb|
          values=comb.map {|a,b| b }
          keys=comb.map {|a,b| a }
          # number of permutations of these given keys
          permutation_number=Rational((1..(keys.size)).reduce(1,:*),keys.uniq.map {|e| (1..(keys.count(e))).reduce(1,:*)}.inject(:*))
          newkeys=mods.inject(keys) { |i,m| m.fun(i) }
          if newkeys.size==0
            @d[0]+=values.inject(:*)*permutation_number
          else
            @d[newkeys.inject(:+)]+=values.inject(:*)*permutation_number
          end
        end
      end
    end
  end

  # n choose k
  def choose(n,k)
    pTop = (n-k+1 .. n).inject(1, &:*) 
    pBottom = (1 .. k).inject(1, &:*)
    pTop / pBottom
  end

  # number of steps
  def stepnum(density_size,comb_length)
    choose(density_size+comb_length-1,comb_length)
  end
end

# density of an exploding die which doesn't reroll maximal values (with modifiers!)
# "density" is the density of the basic reroll (maximum is also rerolled!) die
# "max" is the maximal die number (i.e. the one causing an explosion)
# "number" is the Density of the number of rolled dices
# (i.e. number-1 is the density of the number of explosions)
# "modifiers" is as usual a list of modifiers
class ExplodingDieDensity < Density
  def initialize(density,max,number,modifiers=[])
    (modifiers.is_a? Array) ? mods=modifiers : mods=[modifiers]

    # if we have a distribution of numbers given by a density
    if (number.is_a? Density)
      initial_density=Density.new;
      initial_density.delete[0];

      z=number.inject(initial_density) do |i,(n,p)|
        temp_density=Density.new
        temp_density.delete(0)
        density.each do |k,v|
          newkeys = (modifiers==[]) ? ([max]*(n-1) << k) : mods.inject([max]*(n-1) << k) { |i,m| m.fun(i) }
          if newkeys.size==0
            temp_density[0]+=v
          else
            temp_density[newkeys.inject(:+)]+=v
          end
        end
        i=i.add(temp_density.mult(p))
      end

      @d=z.d
      @fail=false
      @exact=true
      @uniform=false
    end
  end
end
