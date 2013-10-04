#!/usr/bin/ruby -Ilib

require  'd20code'

if (ARGV.length>0)
  parser=(Dice::Parser.new ARGV[0].dup)

  puts parser.roll
  puts parser.output
else
  print "Usage: test.rb <string>\n"
end
