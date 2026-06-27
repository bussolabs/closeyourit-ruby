# frozen_string_literal: true

require_relative "capture_exceptions"
require_relative "request_context"
require_relative "active_job_extension"
require_relative "error_subscriber"
require_relative "../sidekiq/error_handler"
require_relative "query_source"
require_relative "../subscribers/slow_query"

module CloseYourIt
  module Rails
    # Aggancia il client a Rails: Rack middleware di cattura eccezioni +
    # subscriber `sql.active_record` per le query lente.
    class Railtie < ::Rails::Railtie
      initializer "closeyourit.use_rack_middleware" do |app|
        app.config.middleware.use CloseYourIt::Rails::CaptureExceptions
        # RequestContext deve AVVOLGERE CaptureExceptions: lo scope dev'essere già popolato
        # quando l'eccezione risale a CaptureExceptions.
        app.config.middleware.insert_before(
          CloseYourIt::Rails::CaptureExceptions,
          CloseYourIt::Rails::RequestContext
        )
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
          subscriber.breadcrumb(
            name: event.payload[:name],
            sql: event.payload[:sql],
            duration_ms: event.duration,
            cached: event.payload.fetch(:cached, false)
          )
        end
      end

      # Cattura gli errori di ActiveJob/Solid Queue (around_perform).
      initializer "closeyourit.active_job" do
        ActiveSupport.on_load(:active_job) do
          include CloseYourIt::Rails::ActiveJobExtension
        end
      end

      # Cattura gli errori HANDLED riportati via Rails.error.report (Rails 7+).
      initializer "closeyourit.error_reporter" do
        if ::Rails.respond_to?(:error) && ::Rails.error.respond_to?(:subscribe)
          ::Rails.error.subscribe(CloseYourIt::Rails::ErrorSubscriber.new)
        end
      end

      # Cattura gli errori dei job Sidekiq (solo se Sidekiq è presente).
      initializer "closeyourit.sidekiq" do
        if defined?(::Sidekiq) && ::Sidekiq.respond_to?(:configure_server)
          ::Sidekiq.configure_server do |sidekiq_config|
            sidekiq_config.error_handlers << CloseYourIt::Sidekiq::ErrorHandler.new
          end
        end
      end
    end
  end
end
