# frozen_string_literal: true

require "securerandom"
require_relative "../event"
require_relative "../scrubber"

module CloseYourIt
  # Payload `kind=slow_method` per la pipeline metriche. Di default solo label + durata + posizione.
  # Gli argomenti del metodo sono inviati SOLO se `capture_method_arguments` (opt-in, default OFF):
  # posizionali per indice, kwargs per nome (scrub della chiave sensibile), valore via `inspect`
  # troncato per sicurezza JSON. Vedi PDR §9.
  class SlowMethodEvent < Event
    def initialize(label, duration_ms, location, configuration, args: nil, kwargs: nil)
      super(configuration)
      @label = label
      @duration_ms = duration_ms
      @location = location
      @args = args
      @kwargs = kwargs
      @scrubber = Scrubber.new(configuration)
    end

    def to_h
      compact(
        "kind" => "slow_method",
        "sample_id" => SecureRandom.uuid,
        "duration_ms" => @duration_ms.round(2),
        "occurred_at" => @occurred_at,
        "environment" => environment,
        "label" => @label,
        "file" => @location&.path,
        "lineno" => @location&.lineno,
        "arguments" => arguments,
        "sdk" => sdk
      )
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/metrics"
    end

    private

    # Argomenti — SOLO se capture_method_arguments (opt-in). Posizionali per indice; kwargs per nome con
    # scrub della chiave sensibile (denylist password/token/…). Valore = inspect troncato (JSON-safe).
    def arguments
      return nil unless @configuration.capture_method_arguments

      list = Array(@args).each_with_index.map { |arg, i| { "name" => "arg#{i + 1}", "value" => safe_value(arg) } }
      (@kwargs || {}).each do |key, value|
        list << { "name" => key.to_s, "value" => @scrubber.filter_value(key, safe_value(value)) }
      end
      list
    end

    def safe_value(value)
      inspected = value.inspect.to_s
      inspected.length > 120 ? "#{inspected[0, 117]}…" : inspected
    end
  end
end
