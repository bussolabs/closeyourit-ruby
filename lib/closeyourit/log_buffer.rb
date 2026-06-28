# frozen_string_literal: true

require "concurrent"

module CloseYourIt
  # Buffer in-memory thread-safe dei log: accumula i LogEvent e li flusha in batch verso /logs quando
  # raggiungono `logs_batch_size`, allo scadere di `logs_flush_interval` (timer), o allo shutdown.
  # Riduce le richieste HTTP — i log sono alto-volume, a differenza di errori/metriche uno-a-uno.
  class LogBuffer
    attr_reader :timer # esposto per i test (verifica dell'intervallo configurato)

    def initialize(client:, configuration:)
      @client = client
      @configuration = configuration
      @mutex = Mutex.new
      @events = []
      @timer = nil
    end

    def add(event)
      reached_batch = false
      @mutex.synchronize do
        @events << event
        ensure_timer
        reached_batch = @events.size >= @configuration.logs_batch_size.to_i
      end
      flush if reached_batch
    end

    def flush
      batch = drain
      return if batch.empty?

      @client.flush_logs(batch)
    end

    def shutdown
      @timer&.shutdown
      flush
    end

    private

    def drain
      @mutex.synchronize do
        events = @events
        @events = []
        events
      end
    end

    # Avvia il timer di flush periodico alla prima voce (una sola volta).
    def ensure_timer
      return if @timer

      interval = @configuration.logs_flush_interval.to_f
      return if interval <= 0

      @timer = Concurrent::TimerTask.new(execution_interval: interval) { flush }
      @timer.execute
    end
  end
end
