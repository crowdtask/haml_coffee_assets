module HamlCoffeeAssets
  module Processor
    VERSION = '1'

    def self.cache_key
      @cache_key ||= "#{name}:#{HamlCoffeeAssets::VERSION}:#{VERSION}".freeze
    end

    def self.call(input)
      context = input[:environment].context_class.new(input)
      jst =  !!(input[:filename].to_s =~ /\.jst\.hamlc(?:\.|$)/)

      name = context.logical_path

      name = HamlCoffeeAssets.config.name_filter.call(name) if HamlCoffeeAssets.config.name_filter && !jst

      input[:cache].fetch([self.cache_key, input[:data]]) do
        HamlCoffeeAssets::Compiler.compile(name, input[:data], !jst)
      end
    end
  end
end
