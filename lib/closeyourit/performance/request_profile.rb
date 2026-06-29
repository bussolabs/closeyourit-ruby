# frozen_string_literal: true

module CloseYourIt
  module Performance
    # Accumulatore per-richiesta (vive nello Scope, resettato a fine richiesta). Conta le query, le
    # raggruppa per [fingerprint SQL offuscato, call-site] (il pattern prosopite per l'N+1) e tiene le
    # chiamate HTTP esterne. Puro stato in memoria: il verdetto lo calcola Performance::Rollup.
    class RequestProfile
      # Guard di memoria: cap ai gruppi/chiamate distinti tracciati (il conteggio totale resta esatto).
      MAX_GROUPS = 1000
      MAX_EXTERNAL = 500

      attr_reader :query_count, :total_query_time_ms, :query_groups, :external_calls

      def initialize
        @query_count = 0
        @total_query_time_ms = 0.0
        @query_groups = {}
        @external_calls = []
      end

      # Una query non di sistema. Le query da cache non sono round-trip DB → non contano per l'N+1.
      def add_query(fingerprint:, source:, duration_ms:, cached: false)
        return if cached

        ms = duration_ms.to_f
        @query_count += 1
        @total_query_time_ms += ms

        key = "#{fingerprint}\n#{source}"
        group = @query_groups[key]
        if group
          group[:count] += 1
          group[:duration_ms] += ms
        elsif @query_groups.size < MAX_GROUPS
          @query_groups[key] = { count: 1, duration_ms: ms, sql: fingerprint, source: source }
        end
      end

      def add_external(host:, path:, duration_ms:)
        return if @external_calls.size >= MAX_EXTERNAL

        @external_calls << { host: host, path: path, duration_ms: duration_ms.to_f }
      end

      def empty?
        @query_count.zero? && @external_calls.empty?
      end
    end
  end
end
