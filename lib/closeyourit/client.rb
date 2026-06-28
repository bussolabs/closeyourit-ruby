# frozen_string_literal: true

module CloseYourIt
  # Compone Transport + BackgroundWorker: applica `before_send` e dispatcha
  # l'invio in modo fire-and-forget.
  class Client
    def initialize(configuration)
      @configuration = configuration
      @transport = Transport.new(configuration)
      @worker = BackgroundWorker.new(
        threads: configuration.async_threads,
        max_queue: configuration.background_worker_max_queue
      )
    end

    def capture_event(event)
      payload = event.to_h
      payload = @configuration.before_send.call(payload) if @configuration.before_send
      return nil if payload.nil?

      path = event.ingest_path(@configuration.project_id)
      accepted = @worker.perform { @transport.send_event(payload, path: path) }
      CloseYourIt.stats.increment(:enqueued) if accepted
      payload
    end

    # Invia un batch di log come ARRAY a /logs (l'endpoint accetta singolo o array). before_send è
    # applicato a ciascun payload; quelli scartati (nil) non vengono inviati.
    def flush_logs(events)
      return nil if events.nil? || events.empty?

      payloads = events.map(&:to_h)
      payloads = payloads.filter_map { |payload| @configuration.before_send.call(payload) } if @configuration.before_send
      return nil if payloads.empty?

      path = events.first.ingest_path(@configuration.project_id)
      @worker.perform { @transport.send_event(payloads, path: path) }
      payloads
    end

    def shutdown
      @worker.shutdown
    end
  end
end
