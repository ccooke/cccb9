#!/usr/bin/ruby

load './dice.rb'

pp (Dice::Parser.new ARGV[0].dup).terms.inject(Density.new) { |i,term| i+=term.density }
  
#diedensity = ([DieDensity.new(3,[2])]*5).inject(:+)
#puts "Probability to have <=10 for 5d3r2:"
#pp (diedensity<=10)
#moddensity = ModifiedDieDensity.new(diedensity,3,StandardModifier.new)
#puts "Probability to have >40 for 3(5d3r2):"
#pp moddensity>40 
