# frozen_string_literal: true

module CloseYourIt
  # Compone Transport + BackgroundWorker: applica `before_send` e dispatcha
  # l'invio in modo fire-and-forget.
  class Client
    # Tetto di log per singola richiesta a /logs. Il backend rifiuta un batch oltre questo limite
    # (413 R413-LOG-002) scartando l'INTERA richiesta — e il buffer è già stato drenato → log persi.
    # Deve restare ≤ del limite server (LOGS_MAX_BATCH backend = 1000). Vedi #flush_logs.
    LOGS_MAX_BATCH = 1000

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
    # applicato a ciascun payload; quelli scartati (nil) non vengono inviati. I payload oltre
    # LOGS_MAX_BATCH sono spezzati in più POST sequenziali (un chunk = un POST), così un flush grande
    # non viene rigettato in blocco dal backend e perso — vedi R3 / LOGS_MAX_BATCH. Un flush entro il
    # limite resta un singolo POST.
    def flush_logs(events)
      return nil if events.nil? || events.empty?

      payloads = events.map(&:to_h)
      payloads = payloads.filter_map { |payload| @configuration.before_send.call(payload) } if @configuration.before_send
      return nil if payloads.empty?

      path = events.first.ingest_path(@configuration.project_id)
      payloads.each_slice(LOGS_MAX_BATCH) do |chunk|
        @worker.perform { @transport.send_event(chunk, path: path) }
      end
      payloads
    end

    def shutdown
      @worker.shutdown
    end
  end
end
