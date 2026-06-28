# frozen_string_literal: true

require "concurrent"

module CloseYourIt
  # Esegue l'invio fire-and-forget. Con `threads == 0` esegue sincrono (test/dev);
  # altrimenti usa una thread-pool con coda bounded e `fallback_policy: :discard`
  # (se la coda è piena l'evento si perde, mai backpressure sulla request).
  class BackgroundWorker
    attr_reader :executor

    def initialize(threads:, max_queue: 30)
      @executor = build_executor(threads.to_i, max_queue)
    end

    # Ritorna true se l'evento è stato accettato (o eseguito sincrono), false se scartato
    # perché la coda era piena (`fallback_policy: :discard`). Mai backpressure sulla request.
    def perform(&block)
      accepted = @executor.post do
        block.call
      rescue Exception => e # rubocop:disable Lint/RescueException
        # Mai propagare: la telemetria non deve poter crashare l'app ospite.
        CloseYourIt.logger.error("CloseYourIt background worker: #{e.class}: #{e.message}")
      end

      unless accepted
        CloseYourIt.stats.increment(:dropped)
        CloseYourIt.logger.warn("CloseYourIt background worker: coda piena, evento scartato")
      end

      accepted
    end

    def shutdown(timeout = 1)
      return unless @executor.respond_to?(:shutdown)

      @executor.shutdown
      @executor.wait_for_termination(timeout)
    end

    private

    def build_executor(threads, max_queue)
      return Concurrent::ImmediateExecutor.new if threads <= 0

      Concurrent::ThreadPoolExecutor.new(
        min_threads: 0,
        max_threads: threads,
        max_queue: max_queue,
        fallback_policy: :discard
      )
    end
  end
end
