# frozen_string_literal: true

require "securerandom"
require "socket"
require_relative "../event"
require_relative "../scrubber"

module CloseYourIt
  # Trasforma un'eccezione Ruby nel **payload evento Sentry** che il backend CloseYourIt ingerisce
  # (Errors::Ingest::Normalize). Usa `backtrace_locations` (niente regex) e mette la cause-chain in
  # `exception.values` ordinata dall'esterna alla principale (Sentry: values.last = il crash).
  class ErrorEvent < Event
    def self.from_exception(exception, configuration:, handled: false, level: "error", contexts: nil)
      new(exception, configuration, handled: handled, level: level, contexts: contexts)
    end

    def initialize(exception, configuration, handled: false, level: "error", contexts: nil)
      super(configuration)
      @exception = exception
      @handled = handled
      @level = level
      @contexts = contexts
      @scrubber = Scrubber.new(configuration)
    end

    def to_h
      base = compact(
        "event_id" => SecureRandom.uuid.delete("-"),
        "timestamp" => @occurred_at,
        "platform" => "ruby",
        "level" => @level,
        "environment" => environment,
        "release" => @configuration.release,
        "server_name" => server_name,
        "exception" => { "values" => exception_values },
        "contexts" => { "runtime" => { "name" => "ruby", "version" => RUBY_VERSION } },
        "sdk" => sdk
      )
      # Fonde il contesto per-richiesta/job (user/tags/extra/contexts/request) raccolto nello Scope.
      merged = deep_merge(base, CloseYourIt::Scope.current.to_event_hash)
      # Context extra passato esplicitamente (es. rails_error dall'ErrorReporter).
      @contexts ? deep_merge(merged, { "contexts" => @contexts }) : merged
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/events"
    end

    private

    # Cause-chain → array Sentry: causa più esterna prima, eccezione principale ULTIMA.
    def exception_values
      chain = []
      seen = []
      current = @exception
      while current && !seen.include?(current)
        chain << single_exception(current)
        seen << current
        current = current.cause
      end
      chain.reverse
    end

    def single_exception(exception)
      {
        "type" => exception.class.name,
        "value" => @scrubber.scrub_message(exception.message),
        "stacktrace" => { "frames" => frames(exception.backtrace_locations) },
        "mechanism" => { "type" => "ruby", "handled" => @handled }
      }
    end

    # Sentry-style: frame più recente per ultimo; chiavi filename/function/lineno/in_app/abs_path.
    def frames(locations)
      return [] if locations.nil?

      locations.reverse.map do |loc|
        {
          "filename" => loc.path,
          "abs_path" => loc.path,
          "function" => loc.label,
          "lineno" => loc.lineno,
          "in_app" => in_app?(loc.path)
        }
      end
    end

    def in_app?(path)
      return false if path.nil?

      !path.include?("/gems/") && !path.include?(RbConfig::CONFIG["rubylibdir"].to_s)
    end
  end
end
