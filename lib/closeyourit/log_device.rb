# frozen_string_literal: true

module CloseYourIt
  # Oggetto Logger-compatibile esposto come `CloseYourIt.logger`: ogni chiamata inoltra a
  # `CloseYourIt.log` (→ ingest /logs). Usabile come logger esplicito dell'app, anche con attributes:
  #   CloseYourIt.logger.warn("disco quasi pieno", disk: "sda1")
  # `warn` mappa sul livello `warning` (enum backend); supporta block e `::Logger#add` per drop-in.
  class LogDevice
    # Severità numeriche ::Logger → livelli CloseYourIt (UNKNOWN→fatal).
    SEVERITY_LEVELS = { 0 => "debug", 1 => "info", 2 => "warning", 3 => "error", 4 => "fatal", 5 => "fatal" }.freeze

    def debug(message = nil, **attributes, &block) = write("debug", message, attributes, &block)
    def info(message = nil, **attributes, &block)  = write("info", message, attributes, &block)
    def warn(message = nil, **attributes, &block)  = write("warning", message, attributes, &block)
    def error(message = nil, **attributes, &block) = write("error", message, attributes, &block)
    def fatal(message = nil, **attributes, &block) = write("fatal", message, attributes, &block)

    def <<(message)
      write("info", message, {})
      message
    end

    # Compat con ::Logger#add(severity, message = nil, progname = nil).
    def add(severity, message = nil, progname = nil, &block)
      write(SEVERITY_LEVELS.fetch(severity.to_i, "info"), message || progname, {}, &block)
    end
    alias log add

    private

    def write(level, message, attributes, &block)
      # Gate PRIMA del block: `logger.debug { dump_costoso }` non valuta il block se i log sono spenti.
      return unless CloseYourIt.logs_active?

      message = block.call if block
      CloseYourIt.log(level, message, **attributes)
    end
  end
end
