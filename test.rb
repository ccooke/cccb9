#!/usr/bin/ruby

require_relative 'dice'


parser=(Dice::Parser.new ARGV[0].dup)
density=parser.density

if (density.fail)
  print "FAILURE!\n"
elsif (density>=-200)==1
  print "Densities sum up to 1 (OK)!\n"
else
  print "Error: ", Rational(1-(density>=-200)).to_f, "\n"
end
if (density.uniform and (not density.fail))
  print "We have a uniform density.\n"
end
print "Expected value: "
pp parser.expect
print "Density: "
pp density
print "Probability that X<=5: "
print density<=5, "\n"
