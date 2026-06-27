# frozen_string_literal: true

require "securerandom"
require_relative "../event"
require_relative "../scrubber"

module CloseYourIt
  # Payload `kind=slow_query` per la pipeline metriche (`/api/v1/projects/:id/metrics`).
  # Lo SQL è offuscato (binds esclusi) — vedi PDR §9.
  class SlowQueryEvent < Event
    def initialize(payload, duration_ms, configuration)
      super(configuration)
      @payload = payload
      @duration_ms = duration_ms
      @scrubber = Scrubber.new(configuration)
    end

    def to_h
      compact(
        "kind" => "slow_query",
        "sample_id" => SecureRandom.uuid,
        "duration_ms" => @duration_ms.round(2),
        "occurred_at" => @occurred_at,
        "environment" => environment,
        "sql" => @scrubber.obfuscate_sql(@payload[:sql]),
        "name" => @payload[:name],
        "cached" => @payload.fetch(:cached, false),
        "db_system" => db_system,
        "sdk" => sdk
      )
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/metrics"
    end

    private

    def db_system
      connection = @payload[:connection]
      return nil unless connection.respond_to?(:adapter_name)

      connection.adapter_name.to_s.downcase
    end
  end
end
