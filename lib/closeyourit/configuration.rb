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

    # Header HTTP catturati nel contesto request (mai Authorization/Cookie → niente PII/segreti).
    DEFAULT_REQUEST_HEADER_ALLOWLIST = %w[Accept Content-Type User-Agent Referer].freeze

    attr_accessor :endpoint_url, :token, :project_id, :environment, :before_send,
                  :async_threads, :background_worker_max_queue,
                  :slow_query_threshold_ms, :slow_method_threshold_ms,
                  :send_pii, :obfuscate_sql, :send_server_name,
                  :capture_query_bindings, :capture_method_arguments,
                  :capture_request, :request_header_allowlist,
                  :breadcrumbs_enabled, :max_breadcrumbs, :sample_rate,
                  :capture_handled_errors, :report_active_job_errors,
                  :logs_enabled, :logs_sample_rate, :logs_batch_size, :logs_flush_interval,
                  :capture_rails_logs, :logs_min_level,
                  :detect_performance_issues, :n_plus_one_threshold, :query_count_threshold,
                  :query_time_threshold_ms, :slow_request_threshold_ms, :slow_external_threshold_ms,
                  :capture_external_http
    attr_writer :release
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

      # Contesto HTTP della richiesta (method/url/header allowlist). Body/query/IP solo con send_pii.
      @capture_request          = true
      @request_header_allowlist = DEFAULT_REQUEST_HEADER_ALLOWLIST.dup

      # Breadcrumbs: cronologia (query offuscate, eventi custom) allegata all'errore.
      @breadcrumbs_enabled = true
      @max_breadcrumbs     = 100

      # Sampling probabilistico di errori/messaggi (1.0 = invia tutto, 0.0 = niente).
      @sample_rate = 1.0

      # Cattura errori handled (Rails.error.report) e degli ActiveJob/Sidekiq (oggi persi).
      @capture_handled_errors   = true
      @report_active_job_errors = true

      # Cattura valori dei parametri — opt-in, default OFF (privacy). I bind/argomenti possono contenere PII.
      @capture_query_bindings   = false
      @capture_method_arguments = false

      # Log strutturati (CloseYourIt.log / .logger). Master switch + sampling + batching dedicati.
      @logs_enabled        = true
      @logs_sample_rate    = 1.0
      @logs_batch_size     = 50
      @logs_flush_interval = 5
      # Broadcast opt-in di Rails.logger → CloseYourIt.log (default OFF; spedisce solo ≥ soglia).
      @capture_rails_logs = false
      @logs_min_level     = :info

      # Performance issue detection (verdetti aggregati: N+1, slow request, HTTP esterne lente).
      # OPT-IN, default OFF: profila OGNI query della richiesta → overhead non trascurabile, va attivato
      # consapevolmente per-app. Le soglie sono conservative (poco rumore). Vedi Performance::Rollup.
      @detect_performance_issues = false
      @n_plus_one_threshold      = 10        # stesso fingerprint+call-site eseguito > N volte in una richiesta
      @query_count_threshold     = 100       # troppe query totali in una richiesta
      @query_time_threshold_ms   = 500       # tempo DB totale per richiesta oltre cui = high_query_count
      @slow_request_threshold_ms = 1000      # durata totale della richiesta
      @slow_external_threshold_ms = 1000     # singola chiamata HTTP esterna
      @capture_external_http     = true      # strumenta Net::HTTP (solo se detect_performance_issues)

      @filter_parameters      = []
      @scrub_message_patterns = []
    end

    # Classi/stringhe → nome (String); i Regexp restano Regexp (match per pattern su nome/messaggio).
    def excluded_exceptions=(list)
      @excluded_exceptions = Array(list).map { |item| item.is_a?(Regexp) ? item : item.to_s }
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

    # Logga i warning di configurazione (es. endpoint http://, project_id/endpoint malformati).
    # Non solleva mai: coerente con la filosofia no-op del client. Chiamata da `CloseYourIt.init`.
    def validate!
      CloseYourIt.internal_logger.warn(insecure_endpoint_message) if insecure_endpoint?
      CloseYourIt.internal_logger.warn(malformed_project_id_message) if malformed_project_id?
      CloseYourIt.internal_logger.warn(malformed_endpoint_message) if malformed_endpoint?
      self
    end

    # Release effettiva: quella impostata, altrimenti auto-rilevata (ENV di deploy/CI o git).
    def release
      return @release unless @release.nil?

      @release = detect_release
    end

    # Auto-rilevamento release dalle env di deploy/CI o dal git short SHA. Mai solleva.
    def detect_release
      ENV["KAMAL_VERSION"] ||
        ENV["GIT_SHA"] ||
        ENV["GIT_REVISION"] ||
        ENV["SOURCE_VERSION"] ||
        ENV["HEROKU_SLUG_COMMIT"] ||
        git_revision
    rescue StandardError
      nil
    end

    private

    # `.git` è una directory in un checkout normale, un file in un worktree → File.directory?
    # è false nei worktree, così i test non lanciano subprocess git (deterministico).
    def git_revision
      return nil unless File.directory?(".git")

      sha = `git rev-parse --short HEAD 2>/dev/null`.strip
      sha.empty? ? nil : sha
    rescue StandardError
      nil
    end

    UUID_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

    def insecure_endpoint?
      uri = parsed_endpoint
      !uri.nil? && uri.scheme != "https"
    end

    # Avvisa se il project_id è valorizzato ma non sembra uno UUID (l'errore tipico è incollare
    # uno slug/nome al posto dell'id). Non blocca: il server è l'autorità sulla validità.
    def malformed_project_id?
      !blank?(project_id) && !UUID_FORMAT.match?(project_id.to_s)
    end

    def malformed_project_id_message
      "CloseYourIt: project_id (#{project_id}) non ha forma UUID — verifica di aver copiato l'id corretto."
    end

    # Avvisa se endpoint_url è valorizzato ma non parsabile o privo di host.
    def malformed_endpoint?
      return false if blank?(endpoint_url)

      uri = parsed_endpoint
      uri.nil? || blank?(uri.host)
    end

    def malformed_endpoint_message
      "CloseYourIt: endpoint_url (#{endpoint_url}) non è un URL valido (host mancante)."
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
