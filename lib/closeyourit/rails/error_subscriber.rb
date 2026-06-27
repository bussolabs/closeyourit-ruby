# frozen_string_literal: true

module CloseYourIt
  module Rails
    # Sottoscrittore di `ActiveSupport::ErrorReporter` (Rails 7+): cattura gli errori HANDLED
    # riportati via `Rails.error.report`/`Rails.error.handle`. Gli unhandled passano già dal
    # middleware Rack → la dedup (ivar sull'istanza) evita il doppio invio.
    class ErrorSubscriber
      SEVERITY_TO_LEVEL = { error: "error", warning: "warning", info: "info" }.freeze

      # Sorgenti interne rumorose da non inoltrare (evita loop/duplicati).
      IGNORED_SOURCES = %w[closeyourit].freeze

      def report(error, handled:, severity:, context:, source: nil)
        return if source && IGNORED_SOURCES.include?(source)
        return unless CloseYourIt.configuration.capture_handled_errors

        level = SEVERITY_TO_LEVEL.fetch(severity, "error")
        contexts = context && !context.empty? ? { "rails_error" => stringify(context) } : nil
        CloseYourIt.capture_exception(error, handled: handled, level: level, contexts: contexts)
      end

      private

      def stringify(context)
        context.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
      end
    end
  end
end
