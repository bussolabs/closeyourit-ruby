# frozen_string_literal: true

require "uri"
require "concurrent"

module CloseYourIt
  # Tiene tutte le opzioni del client. Costruita da `CloseYourIt.init { |c| ... }`.
  # Senza `endpoint_url`/`token`/`project_id` (o con `http://` in produzione) il client è no-op.
  class Configuration
    DEFAULT_EXCLUDED_EXCEPTIONS = %w[
      ActionController::RoutingError
      ActiveRecord::RecordNotFound
    ].freeze

    attr_accessor :endpoint_url, :token, :project_id, :release, :environment, :before_send,
                  :async_threads, :background_worker_max_queue,
                  :slow_query_threshold_ms, :slow_method_threshold_ms,
                  :send_pii, :obfuscate_sql, :send_server_name
    attr_reader :excluded_exceptions, :filter_parameters, :scrub_message_patterns

    def initialize
      @endpoint_url = ENV.fetch("CLOSEYOURIT_ENDPOINT_URL", nil)
      @token        = ENV.fetch("CLOSEYOURIT_TOKEN", nil)
      @project_id   = ENV.fetch("CLOSEYOURIT_PROJECT_ID", nil)
      @release      = ENV.fetch("CLOSEYOURIT_RELEASE", nil)
      @environment  = ENV.fetch("CLOSEYOURIT_ENVIRONMENT") { detect_environment }

      @excluded_exceptions = DEFAULT_EXCLUDED_EXCEPTIONS.dup
      @before_send         = nil

      @async_threads               = default_threads
      @background_worker_max_queue  = 30

      @slow_query_threshold_ms  = 100
      @slow_method_threshold_ms = 200

      @send_pii         = false
      @obfuscate_sql    = true
      @send_server_name = true

      @filter_parameters      = []
      @scrub_message_patterns = []
    end

    def excluded_exceptions=(list)
      @excluded_exceptions = Array(list).map(&:to_s)
    end

    def filter_parameters=(list)
      @filter_parameters = Array(list)
    end

    def scrub_message_patterns=(list)
      @scrub_message_patterns = Array(list)
    end

    def production?
      environment.to_s == "production"
    end

    # Il client invia solo con credenziali complete (endpoint + token + project_id) e trasporto
    # sicuro (http:// ammesso fuori produzione).
    def enabled?
      return false if blank?(endpoint_url) || blank?(token) || blank?(project_id)
      return false if insecure_endpoint? && production?

      true
    end

    # Logga i warning di configurazione (es. endpoint http://). Chiamata da `CloseYourIt.init`.
    def validate!
      CloseYourIt.logger.warn(insecure_endpoint_message) if insecure_endpoint?
      self
    end

    private

    def insecure_endpoint?
      uri = parsed_endpoint
      !uri.nil? && uri.scheme != "https"
    end

    def insecure_endpoint_message
      tail = production? ? "Telemetria DISABILITATA in production." : "Consentito solo in sviluppo."
      "CloseYourIt: endpoint_url usa http:// non sicuro (#{endpoint_url}) — il token viaggerebbe in chiaro. #{tail}"
    end

    def parsed_endpoint
      return nil if blank?(endpoint_url)

      URI.parse(endpoint_url)
    rescue URI::InvalidURIError
      nil
    end

    def detect_environment
      return ::Rails.env.to_s if defined?(::Rails) && ::Rails.respond_to?(:env) && ::Rails.env

      ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
    end

    def default_threads
      [ (Concurrent.processor_count / 2.0).ceil, 1 ].max
    end

    def blank?(value)
      value.nil? || value.to_s.strip.empty?
    end
  end
end
