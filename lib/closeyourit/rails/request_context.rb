# frozen_string_literal: true

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
        CloseYourIt::Scope.current.request = build_request(env) if active?
        @app.call(env)
      ensure
        CloseYourIt::Scope.reset!
      end

      private

      def active?
        CloseYourIt.enabled? && CloseYourIt.configuration.capture_request
      rescue StandardError
        false
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
