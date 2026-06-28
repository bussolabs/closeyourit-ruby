# frozen_string_literal: true

require "logger"

require_relative "closeyourit/version"
require_relative "closeyourit/configuration"
require_relative "closeyourit/breadcrumb"
require_relative "closeyourit/scope"
require_relative "closeyourit/scrubber"
require_relative "closeyourit/stats"
require_relative "closeyourit/background_worker"
require_relative "closeyourit/transport"
require_relative "closeyourit/event"
require_relative "closeyourit/events/error_event"
require_relative "closeyourit/events/message_event"
require_relative "closeyourit/events/slow_query_event"
require_relative "closeyourit/events/slow_method_event"
require_relative "closeyourit/events/log_event"
require_relative "closeyourit/log_device"
require_relative "closeyourit/log_buffer"
require_relative "closeyourit/subscribers/slow_query"
require_relative "closeyourit/instrumenter"
require_relative "closeyourit/monitor"
require_relative "closeyourit/client"
require_relative "closeyourit/rails/capture_exceptions"
require_relative "closeyourit/rails/request_context"
require_relative "closeyourit/rails/log_broadcast"
require_relative "closeyourit/rails/active_job_extension"
require_relative "closeyourit/rails/error_subscriber"
require_relative "closeyourit/sidekiq/error_handler"

# CloseYourIt — client di telemetria (errori + statistiche di query/metodi lenti)
# che invia gli eventi all'endpoint di ingest di CloseYourIt.
#
# Entry point della gemma (file con trattino come `sentry-ruby`):
# `require "closeyourit-ruby"` carica il modulo `CloseYourIt`.
module CloseYourIt
  # Eccezione base interna: usata per evitare loop (le nostre eccezioni non vengono catturate).
  class Error < StandardError; end

  CAPTURED_FLAG = :@__closeyourit_captured

  class << self
    # Configura il client. Senza token/endpoint → no-op.
    def init
      @configuration = Configuration.new
      @client = nil
      @log_buffer = nil
      yield(@configuration) if block_given?
      @configuration.validate!
      register_shutdown_flush
      @configuration
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def configured?
      !@configuration.nil?
    end

    def enabled?
      configuration.enabled?
    end

    # Cattura un'eccezione e la spedisce (fire-and-forget). No-op se disabilitato,
    # se l'eccezione è esclusa o già catturata.
    def capture_exception(exception, handled: false, level: "error", contexts: nil)
      return nil unless enabled?
      return nil if ignored_exception?(exception)
      return nil if exception_captured?(exception)

      mark_captured(exception)
      return nil unless sampled?

      event = ErrorEvent.from_exception(
        exception, configuration: configuration, handled: handled, level: level, contexts: contexts
      )
      client.capture_event(event)
    end

    # Spedisce un evento già costruito (slow_query/slow_method).
    def capture_event(event)
      return nil unless enabled?

      client.capture_event(event)
    end

    # Invia un messaggio diagnostico esplicito (non un'eccezione). Soggetto a sampling + scope.
    #   CloseYourIt.capture_message("cache miss storm", level: "warning")
    def capture_message(message, level: "info")
      return nil unless enabled?
      return nil unless sampled?

      event = MessageEvent.new(message, level: level, configuration: configuration)
      client.capture_event(event)
    end

    # Cronometra un blocco e invia un slow_method se supera la soglia.
    #   CloseYourIt.measure("checkout.total") { ... }
    def measure(label, &block)
      Instrumenter.measure(label, &block)
    end

    # --- Scope per-richiesta/job (user/tags/extra/contexts) ---
    # Arricchiscono l'evento corrente; resettati a fine richiesta/job da middleware e estensioni.

    def set_user(attributes)
      Scope.current.set_user(attributes)
    end

    def set_tag(key, value)
      Scope.current.set_tag(key, value)
    end

    def set_tags(attributes)
      Scope.current.set_tags(attributes)
    end

    def set_context(key, attributes)
      Scope.current.set_context(key, attributes)
    end

    def set_extra(key, value)
      Scope.current.set_extra(key, value)
    end

    def configure_scope
      yield(Scope.current) if block_given?
    end

    def clear_scope
      Scope.reset!
    end

    # Aggiunge una briciola di contesto (query, navigazione, evento custom) all'evento corrente.
    # No-op se breadcrumbs disabilitati; `data` viene scrubato (denylist) prima di essere salvato.
    def add_breadcrumb(message: nil, category: nil, type: "default", level: "info", data: {})
      return nil unless configuration.breadcrumbs_enabled

      scrubbed = data.nil? || data.empty? ? data : Scrubber.new(configuration).filter_params(data)
      Scope.current.add_breadcrumb(
        Breadcrumb.new(message: message, category: category, type: type, level: level, data: scrubbed)
      )
    end

    # Logger interno della gemma (warning/errori diagnostici su stdout). NON è il logging applicativo:
    # per spedire log strutturati a CloseYourIt usa `CloseYourIt.log` / `CloseYourIt.logger`.
    def internal_logger
      @internal_logger ||= default_internal_logger
    end

    attr_writer :internal_logger

    # Logger applicativo Logger-compatibile: inoltra ogni messaggio a `CloseYourIt.log` (→ ingest /logs).
    #   CloseYourIt.logger.info("ordine creato", order_id: 1)
    def logger
      @app_logger ||= LogDevice.new
    end

    # Costruisce e bufferizza una voce di log strutturata (batch verso /logs, fire-and-forget). Il
    # `level` è normalizzato ai livelli canonici (`:warn`→`warning`, downcase; ignoto→`info`). `logger`
    # opzionale = nome della sorgente del log.
    #   CloseYourIt.log(:info, "ordine creato", order_id: 1)
    #   CloseYourIt.log(:warn, "retry", logger: "payments", attempt: 3)
    def log(level, message, logger: nil, **attributes)
      return nil unless logs_enabled?
      return nil unless logs_sampled?

      event = LogEvent.new(message, level: level, attributes: attributes,
                                    logger: logger, configuration: configuration)
      log_buffer.add(event)
      nil
    end

    # Vero se i log sono attivi (master switch + flag): usato da LogDevice per NON valutare i block
    # costosi (`logger.debug { dump }`) quando il logging è spento.
    def logs_active?
      logs_enabled?
    end

    # Forza l'invio dei log bufferizzati (chiamato anche allo shutdown del processo).
    def flush_logs
      @log_buffer&.flush
      nil
    end

    # Contatori diagnostici del client (accodati/scartati/spediti/falliti).
    #   CloseYourIt.stats.to_h # => { enqueued: …, dropped: …, sent: …, failed: … }
    def stats
      @stats ||= Stats.new
    end

    private

    def client
      @client ||= Client.new(configuration)
    end

    def log_buffer
      @log_buffer ||= LogBuffer.new(client: client, configuration: configuration)
    end

    # I log seguono il master switch del client + il proprio flag dedicato.
    def logs_enabled?
      enabled? && configuration.logs_enabled
    end

    # Sampling indipendente dei log (1.0 = tutti, 0.0 = nessuno).
    def logs_sampled?
      rate = configuration.logs_sample_rate.to_f
      return true if rate >= 1.0
      return false if rate <= 0.0

      Random.rand < rate
    end

    # Allo shutdown del processo svuota i log bufferizzati e ferma il timer (una sola registrazione).
    # Senza, i log sotto-batch dei processi brevi (rake/CLI) andrebbero persi all'uscita.
    def register_shutdown_flush
      return if @shutdown_registered

      @shutdown_registered = true
      at_exit { @log_buffer&.shutdown }
    end

    def ignored_exception?(exception)
      return true if exception.is_a?(CloseYourIt::Error)

      names = exception.class.ancestors.grep(Class).map(&:name).compact
      configuration.excluded_exceptions.any? do |matcher|
        if matcher.is_a?(Regexp)
          names.any? { |name| matcher.match?(name) } || matcher.match?(exception.message.to_s)
        else
          names.include?(matcher)
        end
      end
    end

    # Sampling probabilistico: 1.0 invia sempre, 0.0 mai, intermedio via Random.rand.
    def sampled?
      rate = configuration.sample_rate.to_f
      return true if rate >= 1.0
      return false if rate <= 0.0

      Random.rand < rate
    end

    def exception_captured?(exception)
      exception.instance_variable_defined?(CAPTURED_FLAG)
    end

    def mark_captured(exception)
      exception.instance_variable_set(CAPTURED_FLAG, true)
    end

    def default_internal_logger
      ::Logger.new($stdout).tap do |l|
        l.level = ::Logger::WARN
        l.progname = "CloseYourIt"
      end
    end
  end
end

# Integrazione Rails automatica (solo se Rails è presente).
require_relative "closeyourit/rails/railtie" if defined?(::Rails::Railtie)
