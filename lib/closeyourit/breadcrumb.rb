# frozen_string_literal: true

require "time"

module CloseYourIt
  # Singola briciola di contesto (query, navigazione, evento custom) precedente a un errore.
  # Forma evento Sentry (`breadcrumbs.values[]`). Il `data` è già scrubato a monte (module API).
  class Breadcrumb
    def initialize(message: nil, category: nil, type: "default", level: "info", data: {}, timestamp: nil)
      @timestamp = timestamp || Time.now.utc.iso8601
      @type      = type
      @category  = category
      @level     = level
      @message   = message
      @data      = data
    end

    def to_h
      {
        "timestamp" => @timestamp,
        "type"      => @type,
        "category"  => @category,
        "level"     => @level,
        "message"   => @message,
        "data"      => presence(@data)
      }.reject { |_key, value| value.nil? }
    end

    private

    def presence(value)
      value.nil? || value.empty? ? nil : value
    end
  end
end
