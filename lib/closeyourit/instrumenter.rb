# frozen_string_literal: true

require_relative "events/slow_method_event"

module CloseYourIt
  # Cronometra blocchi/metodi con `CLOCK_MONOTONIC` e invia un `slow_method` se la durata supera la
  # soglia. Gli argomenti sono inviati solo se `capture_method_arguments` (opt-in) — vedi SlowMethodEvent.
  module Instrumenter
    module_function

    def measure(label, args: nil, kwargs: nil)
      location = caller_locations(1, 1)&.first
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
    ensure
      duration_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
      report(label, duration_ms, location, args: args, kwargs: kwargs)
    end

    def report(label, duration_ms, location = nil, args: nil, kwargs: nil)
      config = CloseYourIt.configuration
      return if duration_ms < config.slow_method_threshold_ms

      CloseYourIt.capture_event(
        SlowMethodEvent.new(label, duration_ms, location, config, args: args, kwargs: kwargs)
      )
    end
  end
end
