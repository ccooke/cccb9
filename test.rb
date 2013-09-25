#!/usr/bin/ruby

require_relative 'dice'

result=(Dice::Parser.new ARGV[0].dup).terms.inject(Density.new) { |i,term| i+=term.density }
if (result>=-200)==1
  print "Densities sum up to 1 (OK)!\n"
else
  print "Error: ", Rational(1-(result>=-200)).to_f, "\n"
end
print "Density: "
pp result
print "Probability that X<=5: "
print result<=5, "\n"

#diedensity = ([DieDensity.new(3,[2])]*5).inject(:+)
#puts "Probability to have <=10 for 5d3r2:"
#pp (diedensity<=10)
#moddensity = ModifiedDieDensity.new(diedensity,3,StandardModifier.new)
#puts "Probability to have >40 for 3(5d3r2):"
#pp moddensity>40 
