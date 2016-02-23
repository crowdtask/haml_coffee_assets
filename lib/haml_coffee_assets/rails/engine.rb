# coding: UTF-8

require 'haml_coffee_assets/action_view/resolver'

module HamlCoffeeAssets
  module Rails

    # Haml Coffee Assets Rails engine that can be configured
    # per environment and registers the processor
    #
    class Engine < ::Rails::Engine

      config.hamlcoffee = ::HamlCoffeeAssets.config

      # patch rails so it busts the server cache for templates depending on the
      # global_context_asset.
      #
      # Currently, the only way to force rails to recompile a server template is to
      # touch it. This is problematic because when the global_context_asset
      # changes we need to manually touch every template that uses the congtext
      # in some way.
      #
      # To ease development, make rails 'touch' and recompile hamlc templates
      # when the global context has changed.
      #
      # Do this ONLY in development.

      module PatchActionViewRender
        def stale?
          return false unless ::Rails.env == "development"
          return false unless handler.respond_to?(:stale?)
          handler.stale?(updated_at)
        end

        # by default, rails will only compile a template once
        # path render so it recompiles the template if 'stale'
        def render(view, locals, buffer=nil, &block)
          if @compiled and stale?
            now = Time.now
            File.utime(now, now, identifier) # touch file
            ::Rails.logger.info "Busted cache for #{identifier} by touching it"

            view = refresh(view)
            @source = view.source
            @compiled = false
          end
          super view, locals, buffer, &block
        end
      end

      def haml_coffee_init
        require 'haml_coffee_assets/action_view/template_handler'

        # No server side template support with AMD
        if ::HamlCoffeeAssets.config.placement == 'global'
          # Register Tilt template (for ActionView)
          ActiveSupport.on_load(:action_view) do
            ::ActionView::Template.register_template_handler(:hamlc, ::HamlCoffeeAssets::ActionView::TemplateHandler)
          end

          # Add template path to ActionController's view paths.
          ActiveSupport.on_load(:action_controller) do
            path = ::HamlCoffeeAssets.config.templates_path
            resolver = ::HamlCoffeeAssets::ActionView::Resolver.new(path)
            ::ActionController::Base.append_view_path(resolver)
          end
        end

        if ::Rails.env == "development"
          ::ActionView::Template.prepend PatchActionViewRender
        end
      end

      # Initialize Haml Coffee Assets after Sprockets - TODO: i don't think this
      # really works on sprockets >= 2.x
      #

      register_with_sprockets = if Sprockets::VERSION.to_f < 3
          # sprockets-2.x style
          Proc.new do |app|
            haml_coffee_init
            Sprockets.register_engine '.hamlc', ::HamlCoffeeAssets::Tilt::TemplateHandler
          end
        elsif Sprockets::VERSION.to_f < 4
          # sprockets-3.x style
          Proc.new do |app|
            config.assets.configure do |env|
              haml_coffee_init
              env.register_engine ".hamlc", ::HamlCoffeeAssets::Processor, mime_type: 'application/javascript'
            end
          end
        else
          # sprockets-4.x style
          Proc.new do |app|
            config.assets.configure do |env|
              haml_coffee_init
              # TODO - this should work in 3.x but doesn't - the hamlc is compiled
              # down to js and included correctly but the raw hamlc is also precompiled
              # as foo-hash.hamlc unless the file is .hamlc.erb in which case it becomes
              # foo.hamlc-hash.erb
              require 'sprockets/erb_processor'
              env.register_mime_type 'text/x-haml-coffee', extensions: ['.hamlc'] #, charset: :unicode
              env.register_mime_type 'application/x-haml-coffee+ruby', extensions: ['.hamlc.erb'] #, charset: :unicode

              env.register_transformer 'text/x-haml-coffee', 'application/javascript', ::HamlCoffeeAssets::Processor
              env.register_transformer 'application/x-haml-coffee+ruby', 'text/x-haml-coffee', Sprockets::ERBProcessor
            end
          end
        end

      initializer 'sprockets.hamlcoffeeassets', group: :all, &register_with_sprockets

    end
  end
end
