# frozen_string_literal: true

require "securerandom"

module CloseYourIt
  # Messaggio diagnostico esplicito (`CloseYourIt.capture_message`) nel formato evento Sentry
  # (`message.formatted` + level). Fonde lo Scope corrente come ErrorEvent.
  class MessageEvent < Event
    def initialize(message, level:, configuration:)
      super(configuration)
      @message = message
      @level = level
    end

    def to_h
      base = compact(
        "event_id" => SecureRandom.uuid.delete("-"),
        "timestamp" => @occurred_at,
        "platform" => "ruby",
        "level" => @level,
        "environment" => environment,
        "release" => @configuration.release,
        "server_name" => server_name,
        "message" => { "formatted" => @message },
        "contexts" => { "runtime" => { "name" => "ruby", "version" => RUBY_VERSION } },
        "sdk" => sdk
      )
      deep_merge(base, CloseYourIt::Scope.current.to_event_hash)
    end

    def ingest_path(project_id)
      "/api/v1/projects/#{project_id}/events"
    end
  end
end
