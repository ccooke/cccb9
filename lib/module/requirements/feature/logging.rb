require 'managedthreads'

module Module::Requirements::Feature::Logging
  extend Module::Requirements

  needs :static_methods, :managed_threading

  SPAM = 5
  DEBUG = 4
  VERBOSE = 3
  WARNING = 2
  INFO = 1
  CRITICAL = 0

  %w( VERBOSE SPAM DEBUG WARNING INFO CRITICAL ).each do |word|
    define_method word.downcase.to_sym do |message|
      level = self.class.const_get( word.to_sym )
      @log_queue << [level,message]
    end
  end
  
  def log( string )
    begin
      message = sprintf( "[%s] %s",
        Time.now.strftime("%Y-%m-%d %H:%M:%S"),
        string
      )
      @debug_logfile.puts message # if self.log_to_file
      @debug_logfile.flush
    rescue Exception => e
      puts "DEBUG FAILURE: #{e} #{e.backtrace.inspect}"
    end
  end

  def debug_print level, msg
    log msg if (@loglevel||DEBUG) >= level
  end

  def module_load
    @loglevel = DEBUG
    @log_queue ||= Queue.new
    @debug_logfile = File.open( self.logfile, 'a' ) || STDOUT

    global_methods :info, :warning, :verbose, :debug, :critical, :spam

    ManagedThread.new :logger do
      loop do
        (level,message) = @log_queue.pop
        message.each_line { |m| debug_print level, m }
      end
    end
  end
end

