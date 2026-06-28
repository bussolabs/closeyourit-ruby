# frozen_string_literal: true

require "securerandom"

module CloseYourIt
  # Voce di log strutturata spedita all'ingest /logs (NON formato Sentry: i log sono uno stream con
  # message/level/attributes/logger). Gli `attributes` passano dallo Scrubber (denylist). `trace_id`
  # è preso dallo Scope corrente (popolato per richiesta) → correlazione log↔errori della stessa request.
  class LogEvent < Event
    # Livelli canonici del backend (enum) + alias dei nomi stile ::Logger. Normalizzati QUI (fonte
    # unica) così ogni costruzione — via CloseYourIt.log, .logger o diretta — produce un livello valido.
    LEVELS = %w[debug info warning error fatal].freeze
    LEVEL_ALIASES = { "warn" => "warning", "err" => "error", "unknown" => "fatal" }.freeze

    def initialize(message, level:, attributes:, configuration:, logger: nil)
      super(configuration)
      @message = message
      @level = normalize_level(level)
      @attributes = attributes || {}
      @logger = logger
    end

    def to_h
      compact(
        "event_id" => SecureRandom.uuid.delete("-"),
        "timestamp" => @occurred_at,
        "level" => @level,
        "message" => @message.to_s,
        "attributes" => scrubbed_attributes,
        "logger" => @logger,
        "trace_id" => CloseYourIt::Scope.current.trace_id,
        "environment" => environment,
        "release" => @configuration.release,
        "sdk" => sdk
      )
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/logs"
    end

    private

    def normalize_level(level)
      value = level.to_s.downcase
      value = LEVEL_ALIASES.fetch(value, value)
      LEVELS.include?(value) ? value : "info"
    end

    def scrubbed_attributes
      return {} if @attributes.nil? || @attributes.empty?

      Scrubber.new(@configuration).filter_params(deep_stringify_keys(@attributes))
    end

    # Chiavi sempre stringa (anche annidate): coerenza col payload JSON e con la denylist dello Scrubber.
    def deep_stringify_keys(value)
      case value
      when Hash  then value.each_with_object({}) { |(key, val), acc| acc[key.to_s] = deep_stringify_keys(val) }
      when Array then value.map { |item| deep_stringify_keys(item) }
      else value
      end
    end
  end
end
