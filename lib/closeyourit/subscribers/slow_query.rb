# frozen_string_literal: true

require_relative "../events/slow_query_event"
require_relative "../scrubber"

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

      def record(name:, duration_ms:, sql:, cached: false, connection: nil,
                 binds: nil, type_casted_binds: nil, source: nil)
        config = @configuration || CloseYourIt.configuration
        return if ignored_name?(name)
        return if duration_ms < config.slow_query_threshold_ms

        event = SlowQueryEvent.new(
          { name: name, sql: sql, cached: cached, connection: connection,
            binds: binds, type_casted_binds: type_casted_binds, source: source },
          duration_ms,
          config
        )
        CloseYourIt.capture_event(event)
      end

      # Breadcrumb per OGNI query non di sistema (non solo lente): SQL offuscato, niente bind.
      # Dà la cronologia "quali query prima del crash" allegata all'evento d'errore.
      def breadcrumb(name:, sql:, duration_ms:, cached: false)
        config = @configuration || CloseYourIt.configuration
        return if ignored_name?(name)
        return unless config.breadcrumbs_enabled

        CloseYourIt.add_breadcrumb(
          category: "query",
          type: "query",
          message: Scrubber.new(config).obfuscate_sql(sql),
          data: { "name" => name, "duration_ms" => duration_ms.to_f.round(2), "cached" => cached }
        )
      end

      private

      def ignored_name?(name)
        name.nil? || IGNORED_NAMES.include?(name)
      end
    end
  end
end
