require 'managedthreads'

module Module::Requirements::Feature::Logging
  extend Module::Requirements

  class Logger
    def self.<<(message)
      info message
    end
  end

  class ThreadLessLog
    define_method :<< do |(level,*message)|
      debug_print level, *message
    end
  end

  needs :static_methods

  SPAM = 6
  DEBUG = 5
  VERBOSE = 4
  INFO = 3
  WARNING = 2
  ERROR = 1
  CRITICAL = 0

  %w( SPAM DEBUG VERBOSE INFO WARNING ERROR CRITICAL ).each do |word|
    define_method word.downcase.to_sym do |*message|
      level = self.class.const_get( word.to_sym )
      logging.log_queue << [level,*message]
    end
  end
  
  def log( *strings )
    begin
      strings.each do |string|
        message = sprintf( "[%s] %s",
          Time.now.strftime("%Y-%m-%d %H:%M:%S"),
          string
        )
        logging.logfile.puts message # if self.log_to_file
        logging.logfile.flush
      end
    rescue Exception => e
      puts "DEBUG FAILURE: #{e} #{e.backtrace.inspect}"
    end
  end

  def debug_print level, *msg
    log *msg if (logging.loglevel||DEBUG) >= level
  end

  def module_load
  
    logging.loglevel = VERBOSE
    if have_feature? :managed_threading
      logging.log_queue ||= Queue.new
    else
      logging.log_queue = ThreadLessLog.new
    end
    logging.logfile = File.open( self.logfile, 'a' ) || STDOUT

    global_methods :critical, :error, :warning, :info, :verbose, :debug, :spam, :debug_print
      
  end

  def module_start
    if have_feature? :managed_threading
      logging.log_queue = Queue.new
      ManagedThread.new :logger do
        loop do
          (level,message) = logging.log_queue.pop
          message.each_line { |m| debug_print level, m }
        end
      end
      ManagedThread[:logger].start
      debug "Transitioning to threaded logging"
    end
  end

  def module_unload
    if have_feature? :managed_threading
      logging.saved_queue = logging.log_queue
      old_queue = logging.log_queue
      ManagedThread[:logger].stop
      logging.log_queue = ThreadLessLog.new
      time = Time.now
      until old_queue.empty?
        logging.log_queue << old_queue.pop
      end

      debug "Transitioned to unthreaded logging"
    end
  end
end

