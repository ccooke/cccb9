require 'yaml'
require 'fileutils'
require 'cccb/client'

profile = {
  basedir: ARGV[0],
}


config = YAML.load_file( "#{profile[:basedir]}/conf/profiles/#{ARGV[1]}" )
config.each do |k,v|
  profile[k] = v
end

bot = CCCB::Client.new( profile )

bot.start 
