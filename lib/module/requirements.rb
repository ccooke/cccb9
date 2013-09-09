require 'tsort'
require 'pp'

class Module::TSort
  include TSort

  def initialize(list)
    @list = list
  end

  def tsort_each_node(&block)
    @list.each &block
  end

  def tsort_each_child(mod,&block)
    mod.requirements.each &block
  end
end

module Module::Requirements
  class RequirementMissing < Exception; end
  class CircularDependency < Exception; end

  @@provides = Hash.new { [] }
  @@needs = Hash.new { [] }
  @@sort_cache = Hash.new { [] }

  def self.included(into)
    puts "INCLUDE #{self} INTO #{into}" if $DEBUG
    into.extend(Module::Requirements) unless into.ancestors.include? Module::Requirements
    klass = self
    into.class_exec do
      def included(into)
        puts "SUB #{self} INTO #{into}" if $DEBUG
        missing = requirements.reject { |r| into.ancestors.include? r }
        raise RequirementMissing.new( missing.join(", ") ) unless missing.empty?
        into.provides *@@provides[self]
      end
    end
  end

  def submodules_in_order(klass = nil, ignore_cache = false)
    klass ||= self
    if @@sort_cache.include? klass and not ignore_cache
      puts "Using cached sort order #{@@sort_cache[klass].join(", ")}" if $DEBUG
      return @@sort_cache[klass]
    end
    @@sort_cache[klass] = Module::TSort.new( klass.constants.map { |c|
      const_get(c)
    }.select { |c| 
      c.is_a? Module and not c.is_a? Class
    } ).tsort
    pp "SORTED", @@sort_cache[klass].map { |m| "Module #{m}: NEEDS #{m.requirements.inspect} PROVIDES #{@@provides[m].inspect}" } if $DEBUG
    @@sort_cache[klass]
  end

  def provides? feature
    @@provides[self].include? feature
  end
  def provides(*features)
    @@provides[self] = ( @@provides[self] + features ).uniq
  end
  def needs(*features)
    @@needs[self] = ( @@needs[self] + features ).uniq
  end
  def requirements
    @@needs[self].map { |r| @@provides.keys.find { |m| @@provides[m].include? r } }
  end

end

class Module
  include Module::Requirements
end



