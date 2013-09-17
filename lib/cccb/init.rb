require 'yaml'
require 'fileutils'
require 'pp'
begin
  require 'cccb'

  profile = {
    basedir: ARGV[0],
  }


  config = YAML.load_file( "#{profile[:basedir]}/conf/profiles/#{ARGV[1]}" )
  config.each do |k,v|
    profile[k] = v
  end

  bot = CCCB.new( profile )

  bot.reload_loop
rescue Exception => e
  puts "FATAL :#{e}"
  if $DEBUG
    pp e.backtrace 
  else
    pp e.backtrace[0,2]
  end
end
