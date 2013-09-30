#!/usr/bin/ruby -Ilib

require  'd20code'

if (ARGV.length>0)
  parser=(Dice::Parser.new ARGV[0].dup)
  density=parser.density

  if (density.fail)
    print "The calculation was a failure!\n"
  else
    print "The calculation was a success.\n"
  end
  if (density.exact)
    print "The result is exact.\n"
  else
    print "The result is just an approximation!\n"
  end
  if (density.uniform)
    print "The density is uniform.\n"
  else
    print "The density is probably not uniform!\n"
  end
  
  if (density>-100000)==1
    print "The result is consistent: The densities sum up to 1.\n"
  else
    print "The result is inconsistent. The densities don't sum up to 1 with this error: ", Rational(1-(density>=-1000000)).to_f, "\n"
  end
  
  print "The expected value is: "
  pp parser.expect
  print "The standard deviation is: "
  print density.stdev
  print "\n"
  print "The density plot is: "
  print density.plot
  print "The density is: "
  pp density
  #print "The probability that X<=5 is: "
  #print density<=5, "\n"
else
  print "Usage: test.rb <string>\n"
end
