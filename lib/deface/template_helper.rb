module Deface
  module TemplateHelper
    def lookup_context(view_format)
      @lookup_context ||= {}

      return @lookup_context[view_format] if @lookup_context.has_key?(view_format)

      @lookup_context[view_format] ||= ::ActionView::LookupContext.new(
        ::ActionController::Base.view_paths, {:formats => [view_format]}
      )
    end

    # used to find source for a partial or template using virtual_path
    def load_template_source(virtual_path, partial, apply_overrides=true, lookup_context: nil)
      parts = virtual_path.split("/")

      if parts.size == 2
        prefix = nil
        name = virtual_path
      else
        prefix = [parts.shift]
        name = parts.join("/")
      end

      # if lookup_context.blank?
        view_format = name.include?('.') ? name.split('.').pop.to_sym : :html

        lookup_context ||= self.lookup_context(view_format)
      # end
      name = name.split('.').shift

      view = lookup_context.disable_cache do
        lookup_context.find(name, prefix, partial)
      end

      source =
        if view.handler.to_s == "Haml::Plugin"
          Deface::HamlConverter.new(view.source).result
        elsif view.handler.class.to_s == "Slim::RailsTemplate"
          Deface::SlimConverter.new(view.source).result
        else
          view.source
        end

      if apply_overrides
        begin
          # This needs to be reviewed for production mode, overrides not present
          original_enabled = Rails.application.config.deface.enabled
          Rails.application.config.deface.enabled = apply_overrides

          syntax = Deface::ActionViewExtensions.determine_syntax(view.handler)
          overrides = Deface::Override.find(
            locals: view.instance_variable_get(:@locals),
            format: view.instance_variable_get(:@format),
            variant: view.instance_variable_get(:@variant),
            virtual_path: view.instance_variable_get(:@virtual_path),
          )

          if syntax && overrides.any?
            source = Deface::Override.convert_source(source, syntax: syntax)
            source = Deface::Override.apply_overrides(source, overrides: overrides)
          end
        ensure
          Rails.application.config.deface.enabled = original_enabled
        end
      end

      source
    end

    #gets source erb for an element
    def element_source(template_source, selector)
      doc = Deface::Parser.convert(template_source)

      doc.css(selector).inject([]) do |result, match|
        result << Deface::Parser.undo_erb_markup!(match.to_s.dup)
      end
    end
  end
end
