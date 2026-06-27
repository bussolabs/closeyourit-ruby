# frozen_string_literal: true

require_relative "../events/slow_query_event"

module CloseYourIt
  module Subscribers
    # Riceve i dati di un evento `sql.active_record` e, se la query supera la soglia
    # (escludendo SCHEMA/CACHE/TRANSACTION), invia un evento `slow_query`.
    # Logica pura: il wiring ad ActiveSupport::Notifications vive nel Railtie.
    class SlowQuery
      IGNORED_NAMES = %w[SCHEMA CACHE TRANSACTION].freeze

      def initialize(configuration = nil)
        @configuration = configuration
      end

      def record(name:, duration_ms:, sql:, cached: false, connection: nil)
        config = @configuration || CloseYourIt.configuration
        return if ignored_name?(name)
        return if duration_ms < config.slow_query_threshold_ms

        event = SlowQueryEvent.new(
          { name: name, sql: sql, cached: cached, connection: connection },
          duration_ms,
          config
        )
        CloseYourIt.capture_event(event)
      end

      private

      def ignored_name?(name)
        name.nil? || IGNORED_NAMES.include?(name)
      end
    end
  end
end
