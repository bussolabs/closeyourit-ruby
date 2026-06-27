# frozen_string_literal: true

require "time"

module CloseYourIt
  # Base degli eventi di telemetria. Le sottoclassi implementano `#to_h` e `#ingest_path`
  # (il path API a cui l'evento va spedito: errori → /events, metriche → /metrics).
  class Event
    def initialize(configuration)
      @configuration = configuration
      @occurred_at = Time.now.utc.iso8601
    end

    def to_h
      raise NotImplementedError, "#{self.class} deve implementare #to_h"
    end

    def ingest_path(_project_id)
      raise NotImplementedError, "#{self.class} deve implementare #ingest_path"
    end

    private

    def environment
      @configuration.environment
    end

    def sdk
      { "name" => "closeyourit-ruby", "version" => VERSION }
    end

    def compact(hash)
      hash.reject { |_key, value| value.nil? }
    end
  end
end
