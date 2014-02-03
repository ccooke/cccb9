#!/usr/bin/ruby -Ilib

require  'd20code'

if (ARGV.length>0)
  parser=(Dice::Parser.new ARGV[0].dup)
  parser.roll
  if (ARGV[1] == 'json') 
    require 'json'
    puts( {
      expression: ARGV[0],
      output: parser.output,
      value: parser.value
    }.to_json )
  else
    puts "#{parser.output} = #{parser.value}"
  end
else
  print "Usage: test.rb <string>\n"
end
