# frozen_string_literal: true

require "securerandom"
require_relative "../event"

module CloseYourIt
  # Payload `kind=slow_method` per la pipeline metriche. Solo label + durata + posizione:
  # **mai** gli argomenti del metodo.
  class SlowMethodEvent < Event
    def initialize(label, duration_ms, location, configuration)
      super(configuration)
      @label = label
      @duration_ms = duration_ms
      @location = location
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
        "sdk" => sdk
      )
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/metrics"
    end
  end
end
