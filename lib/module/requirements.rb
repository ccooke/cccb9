require 'tsort'
require 'ostruct'
require 'pp'

class String
  def camel_case
    self.split('_').map(&:capitalize).join
  end

  def snake_case
    self.scan(/[[:upper:]]+[[:lower:]]*/).map(&:downcase).join('_')
  end
end

class Module::TSort
  include TSort

  def initialize(list)
    puts "Init tsort with list #{list}" if $DEBUG
    @list = list
  end

  def tsort_each_node(&block)
    @list.each &block
  end

  def tsort_each_child(mod,&block)
    mod.extend(Module::Requirements) unless mod.singleton_class < Module::Requirements
    puts "TSort: encounter #{mod}: #{mod.requirements}" if $DEBUG
    mod.requirements.each &block
  end
end

module Module::Requirements
  module Feature; 
  end

  module Loader    

    CLEAR_SUBMODULE_CACHE = true

    def submodule_list
      self.constants.map { |c|
        const_get(c)
      }.select { |c| 
        c.is_a? Module and not c.is_a? Class
      } 
    end

    def submodules(ignore_cache = false)
      if not ignore_cache and not @sort_cache.nil?
        puts "Using cached sort order #{@sort_cache.join(", ")}" if $DEBUG
        @sort_cache
      else
        direct_modules = submodule_list
        @sort_cache = Module::TSort.new( direct_modules ).tsort.map { |m|
          unless direct_modules.include? m
            name = ( "AutoDependency" + m.name.gsub( /Module::Requirements::Feature::/, '' ) ).to_sym
            if self.constants.include? name
              self.const_get name
            else
              puts "Dependency #{m} is not direct. Including it into #{self}" if $DEBUG
              self.const_set name, m.dup 
            end
          else
            m
          end
        }
      end
    end

    def included(into)
      # cull!
      puts "Included into #{into} #{self.constants} #{caller_locations.inspect}" if $DEBUG
      into.class_exec(self) do |loader|
        @module_requirements_loader = loader
        @storage ||= Hash.new { OpenStruct.new }
        def self.module_requirements_loader
          @module_requirements_loader
        end
        def have_feature?(feature)
          puts "Is feature #{feature} present in #{self}: #{
            self.class.module_requirements_loader.submodules.each_with_object({}) { |m,h|
              h[m] = m.provides
            }
          }" if $DEBUG
          self.class.module_requirements_loader.submodules.any? { |m| m.provides? feature }
        end
      end
      self.submodules(CLEAR_SUBMODULE_CACHE).each do |m|

        unless ancestors.include? m
          puts "Including module #{m} into #{into}" if $DEBUG
          provide_name = m.provide_name
          into.class_exec do
            include m

            puts "Creating method #{self}.#{provide_name} accessing #{m.name}" if $DEBUG
            
            data = m.name
            define_method :"#{provide_name}" do
              Module::Requirements.storage(data)  
            end

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

  @provides ||= Hash.new { [] }
  @needs ||= Hash.new { [] }
  @sort_cache = Hash.new { [] }
  @storage ||= Hash.new

  def self.provides(obj, *features)
    if features.empty?
      @provides[obj]
    else
      @provides[obj] = ( @provides[obj] + features ).uniq
    end
  end

  def self.provides? obj, feature
    @provides[obj].include? feature
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

  def self.storage(obj)
    @storage[obj] ||= OpenStruct.new
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

      @requirement_class = into
      provides auto_provide
    end
  end
  def provides? feature
    Module::Requirements.provides? @requirement_class, feature
  end
  def provides(*features)
    Module::Requirements.provides(@requirement_class, *features)
  end
  def needs(*features)
    Module::Requirements.needs(@requirement_class, *features)
  end
  def requirements
    Module::Requirements.requirements(@requirement_class)
  end
  
  define_method :provide_name do
    @requirement_class.name.split( '::' ).last.snake_case.to_sym
  end

  @requirement_class = self
end



