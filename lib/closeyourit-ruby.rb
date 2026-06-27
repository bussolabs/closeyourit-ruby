# frozen_string_literal: true

require "logger"

require_relative "closeyourit/version"
require_relative "closeyourit/configuration"
require_relative "closeyourit/breadcrumb"
require_relative "closeyourit/scope"
require_relative "closeyourit/scrubber"
require_relative "closeyourit/background_worker"
require_relative "closeyourit/transport"
require_relative "closeyourit/event"
require_relative "closeyourit/events/error_event"
require_relative "closeyourit/events/message_event"
require_relative "closeyourit/events/slow_query_event"
require_relative "closeyourit/events/slow_method_event"
require_relative "closeyourit/subscribers/slow_query"
require_relative "closeyourit/instrumenter"
require_relative "closeyourit/monitor"
require_relative "closeyourit/client"
require_relative "closeyourit/rails/capture_exceptions"
require_relative "closeyourit/rails/request_context"
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
      yield(@configuration) if block_given?
      @configuration.validate!
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

    def logger
      @logger ||= default_logger
    end

    attr_writer :logger

    private

    def client
      @client ||= Client.new(configuration)
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

    def default_logger
      ::Logger.new($stdout).tap do |l|
        l.level = ::Logger::WARN
        l.progname = "CloseYourIt"
      end
    end
  end
end

# Integrazione Rails automatica (solo se Rails è presente).
require_relative "closeyourit/rails/railtie" if defined?(::Rails::Railtie)
