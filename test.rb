#!/usr/bin/ruby

require_relative 'dice'


result=(Dice::Parser.new ARGV[0].dup).density

if (result>=-200)==1
  print "Densities sum up to 1 (OK)!\n"
else
  print "Error: ", Rational(1-(result>=-200)).to_f, "\n"
end

print "Density: "
pp result
print "Probability that X<=5: "
print result<=5, "\n"
