# frozen_string_literal: true

require "securerandom"
require_relative "../event"

module CloseYourIt
  # Payload `kind=performance_issue` per la pipeline metriche (`/api/v1/projects/:id/metrics`).
  # È un VERDETTO aggregato (N+1, slow request, slow external HTTP), non una metrica grezza:
  # `subtype` lo qualifica, `trace_id` lo correla a log/errori della stessa richiesta. Lo SQL è già
  # offuscato (è il fingerprint del profilo). I campi nil vengono omessi (slow_request non ha sql).
  class PerformanceIssueEvent < Event
    def initialize(attrs, configuration)
      super(configuration)
      @attrs = attrs
    end

    def to_h
      compact(
        "kind" => "performance_issue",
        "subtype" => @attrs[:subtype],
        "sample_id" => SecureRandom.uuid,
        "duration_ms" => @attrs[:duration_ms]&.round(2),
        "occurred_at" => @occurred_at,
        "environment" => environment,
        "trace_id" => @attrs[:trace_id],
        "sql" => @attrs[:sql],
        "source" => @attrs[:source],
        "route" => @attrs[:route],
        "http_host" => @attrs[:http_host],
        "http_url" => @attrs[:http_url],
        "query_count" => @attrs[:query_count],
        "total_query_time_ms" => @attrs[:total_query_time_ms]&.round(2),
        "count_in_request" => @attrs[:count_in_request],
        "sdk" => sdk
      )
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/metrics"
    end
  end
end
