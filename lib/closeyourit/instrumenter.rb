# frozen_string_literal: true

require_relative "events/slow_method_event"

module CloseYourIt
  # Cronometra blocchi/metodi con `CLOCK_MONOTONIC` e invia un `slow_method`
  # se la durata supera la soglia. Mai cattura gli argomenti.
  module Instrumenter
    module_function

    def measure(label)
      location = caller_locations(1, 1)&.first
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
      report(label, duration_ms, location)
    end

    def report(label, duration_ms, location = nil)
      config = CloseYourIt.configuration
      return if duration_ms < config.slow_method_threshold_ms

      CloseYourIt.capture_event(SlowMethodEvent.new(label, duration_ms, location, config))
    end
  end
end
