# Copyright © 2010 Charles Cooke <ccooke-ruby@gkhs.net> 
#
# This was originally written on a weekend to fix a problem in a
# personal project.  To make licensing clear, I'm including a 
# simplified BSD license: 
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are
# met:
#
# * Redistributions of source code must retain the above copyright
# notice, this list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright
# notice, this list of conditions and the following disclaimer in the
# documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
# LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
# THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

class ManagedThread
  class Stop < Exception; end
  class Start < Exception; end
  class Error < Exception; end

  @defaults = {
    :restart => true,
    :state => :started,
    :interval => 5
  }

  @subclasses = []
  @registry = {}

  class << self
    attr_accessor :registry

    [:restart, :state, :interval].each do |sym|
      define_method "default_#{sym}".to_sym do 
        @defaults.include? sym ? @defaults[sym] :self.superclass.send( "default_#{sym}".to_sym )
      end
      define_method "default_#{sym}=".to_sym do |v|
        @defaults[sym] = v
      end
    end
  end

  attr_accessor :block, :restart, :interval, :state
  private :block
  attr_reader :thread, :name

  def initialize(name, args = {}, &block)
    @block = block
    @name = name
    @thread_lock = Mutex.new

    @restart = args[:restart].nil? ? self.class.default_restart : args[:restart]
    @interval = args[:interval].nil? ? self.class.default_interval : args[:interval]
    @state = args[:state].nil? ? self.class.default_state : args[:state]

    puts "Defined #{self.class}:#{self.name}" if $DEBUG
    self.begin
  end

  def to_s
    "Thread:#{@name}"
  end

  def begin
    @thread_lock.lock
    @thread = Thread.new { self.reliable_thread }
    if @state == :started
      @thread_lock.unlock
    end
  end

  def self.new(name,args={},&block)
    if self.registry.include? name
      thread = self.registry[name]
      if block
        thread.block = block
        thread.raise Start.new
      end
    else
      raise Error.new("No such reliable thread exists") unless block.is_a? Proc
      thread = super(name,args,&block)
      self.registry[name] = thread
    end
    thread
  end

  def stop()
    @thread.raise Stop.new
  end

  def start()
    puts "Start #{@thread}"
    @thread_lock.unlock
  end

  def raise(e)
    @thread.raise(e)
  end

  def reliable_thread
    begin
      @thread_lock.lock
      puts "Execute #{self.class}:#{self.name}" 
      loop do
        block.call
        sleep @interval
        self.halt unless @restart
      end
    rescue Stop => e
      retry
    rescue Start => e
      @thread_lock.unlock
      retry
    rescue Exception => e
      puts "Caught exception from reliable thread #{self.name}/#{name}: #{e} #{e.backtrace}" 
      if @restart
        puts "Restarting reliable thread #{self.class}/#{@name} after exception in #{@interval} seconds" 
        sleep @interval
        @thread_lock.unlock
      else
        self.halt
      end
      retry
    end
  end

  def halt
    @state = :stopped
    Thread.stop
    @state = :started
  end

  def kill
    @state = :dead
    @thread.kill
  end

  def restart
    puts "RESTART #{self} #{@thread}"
    self.stop
    self.start
  end

  def self.all_threads
    ( [ self ] + @subclasses ).inject([]) do |a,klass|
      a += klass.threads
    end 
  end

  def self.threads
    return [] if @registry.nil?
    self.registry.values
  end

  def self.thread(name)
    self.registry[name]
  end

  def self.reload_threads
    self.all_threads.map &:restart
  end

  def self.add_subclass(subclass)
    if self == ::ManagedThread
      @subclasses.push subclass
    else
      super(subclass)
    end
  end

  def self.inherited(subclass)
    return unless superclass == ::ManagedThread
    superclass.add_subclass( self )
#    puts "Inherited into #{subclass}. Super is #{self.superclass}" if $DEBUG
    @registry = {}
    @defaults = {}
    @subclasses = []
  end
end

module ThreadCompartment
  def self.included(parent)
    parent.class_eval do
      rclass = Class.new(ManagedThread)
      const_set( 'ManagedThread', rclass )
      rclass.inherited(parent)
    end
  end
end
