# frozen_string_literal: true

require "concurrent"

module CloseYourIt
  # Contatori diagnostici thread-safe del client: quanti eventi sono stati accodati,
  # scartati (coda piena), spediti con successo o falliti (rete o status non-2xx).
  # Servono a rendere visibili i fallimenti silenziosi del trasporto fire-and-forget.
  #
  #   CloseYourIt.stats.to_h # => { enqueued: 12, dropped: 0, sent: 11, failed: 1 }
  class Stats
    COUNTERS = %i[enqueued dropped sent failed].freeze

    def initialize
      @counters = COUNTERS.to_h { |name| [ name, Concurrent::AtomicFixnum.new(0) ] }
    end

    def increment(name)
      counter = @counters.fetch(name)
      counter.increment
      counter.value
    end

    def [](name)
      @counters.fetch(name).value
    end

    def to_h
      @counters.transform_values(&:value)
    end

    def reset!
      @counters.each_value { |counter| counter.value = 0 }
      self
    end
  end
end
