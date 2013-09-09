
module CCCB
  module Util
    module Config
      def configure(args)
      end

      def config(key)
        @config[key]
      end

      def initialize(args)
        @config = configure(args)

        @config.keys.each do |key|
          self.metaclass.class_exec(key,@config) do |k,c|
            define_method k.to_sym do
              c[k]
            end

            define_method :"#{k}=" do |value|
              c[k] = value
            end
          end
        end

      end
    end
  end
end

