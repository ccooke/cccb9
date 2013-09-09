
module CCCB
  class Client
    module Core
      class MissingFeature < Exception; end

      @@features = {}

      def self.included(into)
        puts "Included into #{into} #{self.constants}" if $DEBUG
        self.submodules_in_order.each do |m|
          unless ancestors.include? m
            puts "Including module #{m}" if $DEBUG
            into.class_exec do
              include m
            end
          end
        end
      end

    end
  end
end


