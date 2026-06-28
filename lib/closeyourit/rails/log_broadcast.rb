# frozen_string_literal: true

require "logger"

module CloseYourIt
  module Rails
    # Sink Logger-compatibile agganciato a Rails.logger (broadcast opt-in, `config.capture_rails_logs`):
    # ogni log dell'app ≥ soglia (`logs_min_level`) viene re-inoltrato a CloseYourIt.log → ingest /logs.
    # Sotto soglia: no-op (nessun invio). Non scrive su alcun device (inoltra soltanto).
    class LogBroadcast < ::Logger
      SEVERITY_LEVELS = { 0 => "debug", 1 => "info", 2 => "warning", 3 => "error", 4 => "fatal", 5 => "fatal" }.freeze
      LEVEL_BY_SYMBOL = { debug: 0, info: 1, warn: 2, warning: 2, error: 3, fatal: 4 }.freeze

      def initialize(min_level = :info)
        super(nil) # nessun device: inoltra soltanto
        self.level = LEVEL_BY_SYMBOL.fetch(min_level.to_sym, 1)
      end

      # Sovrascrive il punto unico di ::Logger: filtra per soglia e re-inoltra a CloseYourIt.log.
      def add(severity, message = nil, progname = nil)
        severity ||= ::Logger::UNKNOWN
        return true if severity < level

        text = message || (block_given? ? yield : nil) || progname
        CloseYourIt.log(SEVERITY_LEVELS.fetch(severity, "info"), text) unless text.nil?
        true
      end
    end
  end
end
