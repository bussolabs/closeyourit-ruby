# frozen_string_literal: true

require "uri"
require_relative "../scope"

module CloseYourIt
  module Rails
    # Prepended a Net::HTTP: cronometra ogni chiamata esterna e la spinge nel RequestProfile dello
    # Scope, così la finestra della richiesta può rilevare le HTTP esterne lente. Trasparente
    # (restituisce la risposta originale) e difensivo (no-op se la telemetria è off; mai solleva per
    # colpa del profiling). Esclude le chiamate verso l'endpoint CloseYourIt stesso (niente loop).
    module NetHTTPPatch
      def request(req, body = nil, &block)
        config = CloseYourIt.configuration
        return super unless config.detect_performance_issues && config.capture_external_http

        started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          super
        ensure
          duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000.0
          record_external(config, req, duration_ms)
        end
      end

      private

      def record_external(config, req, duration_ms)
        host = address
        return if host.nil? || own_endpoint?(config, host)

        CloseYourIt::Scope.current.performance_profile.add_external(
          host: host, path: templatize_path(req), duration_ms: duration_ms
        )
      rescue StandardError
        # Il profiling non deve mai disturbare la chiamata ospite.
        nil
      end

      def own_endpoint?(config, host)
        endpoint = config.endpoint_url
        return false if endpoint.nil?

        URI.parse(endpoint).host == host
      rescue URI::InvalidURIError
        false
      end

      # Path senza query string, con uuid e run di ≥3 cifre → placeholder (stessa rotta = stessa
      # signature). La soglia ≥3 cifre preserva le versioni API tipo "/v1" e templatizza gli id reali
      # ("/v1/charges/ch_12345" → "/v1/charges/ch_<n>", "/users/123" → "/users/<n>").
      def templatize_path(req)
        path = req.respond_to?(:path) ? req.path.to_s : ""
        path.split("?", 2).first.to_s
            .gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i, "<uuid>")
            .gsub(/\d{3,}/, "<n>")
      end
    end
  end
end
