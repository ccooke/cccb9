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
  class Error < Exception; end

  @defaults = {
    :restart => true,
    :start => true,
    :repeat => 5
  }

  attr_accessor :block, :restart, :repeat, :start
  private :block
  attr_reader :thread, :name

  @subclasses = []
  @registry = {}

  class << self
    attr_accessor :registry

    [:restart, :start, :repeat].each do |sym|
      define_method "default_#{sym}".to_sym do 
        @defaults.include? sym ? @defaults[sym] :self.superclass.send( "default_#{sym}".to_sym )
      end
      define_method "default_#{sym}=".to_sym do |v|
        @defaults[sym] = v
      end
    end
  end

  def self.[](name)
    self.registry[name]
  end

  def self.new(name,args={},&block)
    if self.registry.include? name
      thread = self.registry[name]
      if block
        thread.block = block
        puts "Replacing block in #{thread}" if $DEBUG
        thread.start if thread.start?
      end
    else
      raise Error.new("No such reliable thread exists") unless block.is_a? Proc
      thread = super(name,args,&block)
      self.registry[name] = thread
      thread.start if thread.start?
    end
    thread
  end

  def initialize(name, args = {}, &block)
    @block = block
    @name = name
    @lock = Mutex.new

    @restart = args[:restart].nil? ? self.class.default_restart : args[:restart]
    @repeat = args[:repeat].nil? ? self.class.default_repeat : args[:repeat]
    @start = args[:start].nil? ? self.class.default_start : args[:start]

    puts "Defined #{self.class}:#{self.name}" if $DEBUG
  end

  def start?
    @start
  end

  def to_s
    "ManagedThread:#{@name}"
  end

  def inspect
    "<#{self}:#{@thread.status}>"
  end

  def start()
    return @thread if @lock.locked?
    puts "START #{self}" if $DEBUG
    @thread = Thread.new { self.reliable_thread }
  end

  def stop()  
    return @thread if not @lock.locked?
    puts "STOP #{self}" if $DEBUG
    @thread.kill
    @thread
  end

  def restart()
    stop
    start
  end

  def raise(e)
    @thread.raise(e)
  end

  def reliable_thread
    @lock.synchronize do
      begin
        puts "Execute #{self.class}:#{self.name}" if $DEBUG
        loop do
          block.call
          if @repeat
            sleep @repeat
          else
            break
          end
        end
      rescue Exception => e
        puts "Caught exception from reliable thread #{self.name}/#{name}: #{e} #{e.backtrace}" if $DEBUG
        if @restart
          puts "Restarting reliable thread #{self.class}/#{@name} after exception in #{@repeat || 0} seconds"  if $DEBUG
          sleep @repeat || 0
        else
          self.halt
        end
        retry
      end
    end
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
