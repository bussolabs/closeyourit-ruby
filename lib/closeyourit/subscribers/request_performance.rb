# frozen_string_literal: true

require_relative "../scope"
require_relative "../performance/rollup"

module CloseYourIt
  module Subscribers
    # A fine richiesta (process_action.action_controller) trasforma il RequestProfile accumulato nello
    # Scope in verdetti performance_issue e li spedisce (fire-and-forget). Lo Scope — e quindi il
    # profilo — viene azzerato subito dopo da RequestContext#call (ensure). Logica pura: il wiring ad
    # ActiveSupport::Notifications vive nel Railtie.
    class RequestPerformance
      def initialize(configuration = nil)
        @configuration = configuration
      end

      def record(route:, duration_ms:)
        config = @configuration || CloseYourIt.configuration
        return unless config.detect_performance_issues

        profile = CloseYourIt::Scope.current.performance_profile
        return if profile.empty? && !slow_request?(config, duration_ms)

        events = CloseYourIt::Performance::Rollup.call(
          profile: profile, configuration: config, route: route,
          request_duration_ms: duration_ms, trace_id: CloseYourIt::Scope.current.trace_id
        )
        events.each { |event| CloseYourIt.capture_event(event) }
      end

      private

      def slow_request?(config, duration_ms)
        duration_ms && config.slow_request_threshold_ms && duration_ms > config.slow_request_threshold_ms
      end
    end
  end
end
