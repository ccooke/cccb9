require 'yaml'
require 'fileutils'
require 'cccb'

profile = {
  basedir: ARGV[0],
}


config = YAML.load_file( "#{profile[:basedir]}/conf/profiles/#{ARGV[1]}" )
config.each do |k,v|
  profile[k] = v
end

bot = CCCB.new( profile )

bot.start 
