require 'tsort'
require 'pp'

class String
  def camel_case
    self.split('_').map(&:capitalize).join
  end

  def snake_case
    self.scan(/[[:upper:]]+[[:lower:]]+/).map(&:downcase).join('_')
  end
end

class Module::TSort
  include TSort

  def initialize(list)
    puts "Init tsort with list #{list}"
    pp list.each_with_object({}) { |m,h| h[m] = tsort_each_child(m).to_a }
    @list = list
  end

  def tsort_each_node(&block)
    @list.each &block
  end

  def tsort_each_child(mod,&block)
    mod.extend(Module::Requirements) unless mod.singleton_class < Module::Requirements
    puts "TSort: encounter #{mod}: #{mod.requirements}"
    mod.requirements.each &block
  end
end

module Module::Requirements
  module Feature; 
  end

  module Loader    

    def submodule_list
      self.constants.map { |c|
        const_get(c)
      }.select { |c| 
        c.is_a? Module and not c.is_a? Class
      } 
    end

    def submodules(ignore_cache = false)
      unless @sort_cache.nil? and not ignore_cache
        puts "Using cached sort order #{@sort_cache.join(", ")}" if $DEBUG
        @sort_cache
      else
        @sort_cache = Module::TSort.new( submodule_list ).tsort
      end
    end

    def included(into)
      puts "Included into #{into} #{self.constants}" if $DEBUG
      into.class_exec(self) do |loader|
        @module_requirements_loader = loader
        def self.module_requirements_loader
          @module_requirements_loader
        end
      end
      direct_modules = submodule_list
      self.submodules.each do |m|

        unless direct_modules.include? m
          puts "Dependency #{m} is not direct. Including it into #{self}" if $DEBUG
          name = ( "AutoDependency" + m.name.gsub( /Module::Requirements::Feature::/, '' ) ).to_sym
          m = self.const_set name, m.dup 
        end

        unless ancestors.include? m
          puts "Including module #{m} into #{into}" if $DEBUG
          into.class_exec do
            include m
          end
        end
      end
    end

    def add_feature(const)
     # name = const.name.split('::').last
     # self.const_set( name.to_sym, Module.new { extend const } )
     # puts "Feature: #{const} added as #{self.const_get(name.to_sym)}"
     # puts self.const_get( name.to_sym ).method(:extended)
    end

  end

  class RequirementMissing < Exception; end
  class CircularDependency < Exception; end

  @provides = Hash.new { [] }
  @needs = Hash.new { [] }
  @sort_cache = Hash.new { [] }

  def self.provides(obj, *features)
    if features.empty?
      @provides[obj]
    else
      @provides[obj] = ( @provides[obj] + features ).uniq
    end
  end

  def self.provides? obj, feature
    @@provides[obj].include? feature
  end

  def self.needs(obj, *features)
    @needs[obj] = ( @needs[obj] + features ).uniq
  end

  def self.requirements(obj)
    @needs[obj].map do |r| 
      dep = @provides.keys.find do |m| 
        @provides[m].include? r
      end
      if dep.nil? 
        raise Module::Requirements::RequirementMissing.new(r)
      else
        dep
      end
    end
  end

  def self.extended(into)
    puts "EXTEND #{self} INTO #{into} #{caller_locations(1,1)}" if $DEBUG
    #into.extend(Module::Requirements) unless into.ancestors.include? Module::Requirements
    auto_provide = into.name.split( '::' ).last.snake_case.to_sym
    into.class_exec do
      def included(into)
        puts "SUB #{self} INTO #{into}" if $DEBUG
        into.extend(Module::Requirements) unless into.singleton_class < Module::Requirements
        missing = requirements.reject { |r| into.ancestors.include? r }
        raise RequirementMissing.new( missing.join(", ") ) unless missing.empty?
        into.provides *Module::Requirements.provides(self)
      end

      def extended(into)
        Module::Requirements.extended(into)
      end

      provides auto_provide
    end
  end
  def provides? feature
    @@provides[self].include? feature
    Module::Requirements.provides? self, feature
  end
  def provides(*features)
    Module::Requirements.provides(self, *features)
  end
  def needs(*features)
    Module::Requirements.needs(self, *features)
  end
  def requirements
    Module::Requirements.requirements(self)
  end

end



