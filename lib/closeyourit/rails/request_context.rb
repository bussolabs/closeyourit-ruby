# frozen_string_literal: true

require "securerandom"

module CloseYourIt
  module Rails
    # Rack middleware: popola lo Scope con il contesto HTTP della richiesta (method/url/header)
    # così l'evento d'errore catturato a valle sa "in quale pagina" è capitato. Deve avvolgere
    # `CaptureExceptions` (insert_before) per essere già popolato quando l'eccezione risale.
    # Rack puro (legge `env`, nessuna dipendenza da Rails) → testabile in isolamento.
    class RequestContext
      # Header con prefisso non-HTTP_ in env Rack.
      RAW_HEADERS = %w[CONTENT_TYPE CONTENT_LENGTH].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        if enabled?
          # trace_id sempre (correlazione log↔errori), anche con capture_request OFF.
          CloseYourIt::Scope.current.trace_id = trace_id_for(env)
          if CloseYourIt.configuration.capture_request
            CloseYourIt::Scope.current.request = build_request(env)
            # Riferimento all'env per l'estrazione LAZY del body (request.data) a evento costruito.
            CloseYourIt::Scope.current.rack_env = env
          end
        end
        @app.call(env)
      ensure
        CloseYourIt::Scope.reset!
      end

      private

      def enabled?
        CloseYourIt.enabled?
      rescue StandardError
        false
      end

      # Riusa il request id di Rails/Rack se presente (stessa correlazione dei log applicativi),
      # altrimenti ne genera uno.
      def trace_id_for(env)
        env["action_dispatch.request_id"] ||
          env["HTTP_X_REQUEST_ID"].to_s.split(",").first&.strip.then { |id| id&.empty? ? nil : id } ||
          SecureRandom.uuid
      end

      # Forma `request` Sentry. URL senza query string; header solo dall'allowlist (mai
      # Authorization/Cookie). query_string + IP solo con send_pii (opt-in).
      def build_request(env)
        request = {
          "method"  => env["REQUEST_METHOD"],
          "url"     => build_url(env),
          "headers" => allowed_headers(env)
        }.reject { |_key, value| value.nil? }

        if CloseYourIt.configuration.send_pii
          query = env["QUERY_STRING"]
          request["query_string"] = query if query && !query.empty?
          ip = env["REMOTE_ADDR"]
          request["env"] = { "REMOTE_ADDR" => ip } if ip
        end

        request
      rescue StandardError
        # La telemetria non deve mai disturbare la richiesta ospite.
        nil
      end

      def build_url(env)
        scheme = env["rack.url_scheme"] || "http"
        host = env["HTTP_HOST"] || env["SERVER_NAME"]
        return nil if host.nil?

        "#{scheme}://#{host}#{env["PATH_INFO"]}"
      end

      def allowed_headers(env)
        CloseYourIt.configuration.request_header_allowlist.each_with_object({}) do |name, acc|
          value = env[header_env_key(name)]
          acc[name] = value if value
        end
      end

      def header_env_key(name)
        upcased = name.upcase.tr("-", "_")
        RAW_HEADERS.include?(upcased) ? upcased : "HTTP_#{upcased}"
      end
    end
  end
end
