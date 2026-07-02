# frozen_string_literal: true

require "securerandom"
require "socket"
require_relative "../event"
require_relative "../scrubber"
require_relative "../line_cache"

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
        # Correlazione log↔errori: stesso trace_id dei log della medesima richiesta (popolato dallo Scope).
        "trace_id" => CloseYourIt::Scope.current.trace_id,
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

    # Sentry-style: frame più recente per ultimo; chiavi filename/function/lineno/in_app/abs_path
    # + snippet di sorgente (pre_context/context_line/post_context) quando il file è leggibile.
    def frames(locations)
      return [] if locations.nil?

      context_lines = @configuration.context_lines.to_i
      locations.reverse.map do |loc|
        frame = {
          "filename" => loc.path,
          "abs_path" => loc.path,
          "function" => loc.label,
          "lineno" => loc.lineno,
          "in_app" => in_app?(loc.path)
        }
        add_context!(frame, loc.path, loc.lineno, context_lines) if context_lines.positive?
        frame
      end
    end

    def add_context!(frame, path, lineno, count)
      lines = LineCache.lines(path)
      return if lines.nil? || lineno.nil? || lineno < 1 || lineno > lines.size

      index = lineno - 1
      frame["pre_context"]  = lines[[ index - count, 0 ].max...index]
      frame["context_line"] = lines[index]
      frame["post_context"] = lines[index + 1, count] || []
    end

    def in_app?(path)
      return false if path.nil?

      !path.include?("/gems/") && !path.include?(RbConfig::CONFIG["rubylibdir"].to_s)
    end
  end
end
