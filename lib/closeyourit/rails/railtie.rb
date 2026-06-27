# frozen_string_literal: true

require_relative "capture_exceptions"
require_relative "query_source"
require_relative "../subscribers/slow_query"

module CloseYourIt
  module Rails
    # Aggancia il client a Rails: Rack middleware di cattura eccezioni +
    # subscriber `sql.active_record` per le query lente.
    class Railtie < ::Rails::Railtie
      initializer "closeyourit.use_rack_middleware" do |app|
        app.config.middleware.use CloseYourIt::Rails::CaptureExceptions
      end

      initializer "closeyourit.subscribe_slow_queries" do
        subscriber = CloseYourIt::Subscribers::SlowQuery.new

        ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          subscriber.record(
            name: event.payload[:name],
            duration_ms: event.duration,
            sql: event.payload[:sql],
            cached: event.payload.fetch(:cached, false),
            connection: event.payload[:connection],
            binds: event.payload[:binds],
            type_casted_binds: event.payload[:type_casted_binds],
            source: CloseYourIt::Rails::QuerySource.from_caller
          )
        end
      end
    end
  end
end
