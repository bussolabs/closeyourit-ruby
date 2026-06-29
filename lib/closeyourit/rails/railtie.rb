# frozen_string_literal: true

require_relative "capture_exceptions"
require_relative "request_context"
require_relative "active_job_extension"
require_relative "error_subscriber"
require_relative "../sidekiq/error_handler"
require_relative "query_source"
require_relative "log_broadcast"
require_relative "net_http_patch"
require_relative "../subscribers/slow_query"
require_relative "../subscribers/request_performance"

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
          # Accumula la query nel profilo per-richiesta (detection N+1 a fine richiesta).
          subscriber.profile(
            name: event.payload[:name],
            sql: event.payload[:sql],
            duration_ms: event.duration,
            cached: event.payload.fetch(:cached, false),
            source: CloseYourIt::Rails::QuerySource.from_caller
          )
        end
      end

      # A fine richiesta: trasforma il profilo accumulato in verdetti performance_issue (N+1, slow
      # request, HTTP esterne lente). Il subscriber è no-op se detect_performance_issues è OFF.
      initializer "closeyourit.subscribe_request_performance" do
        perf = CloseYourIt::Subscribers::RequestPerformance.new

        ActiveSupport::Notifications.subscribe("process_action.action_controller") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          payload = event.payload
          perf.record(
            route: "#{payload[:controller]}##{payload[:action]}",
            duration_ms: event.duration
          )
        end
      end

      # Strumenta le chiamate HTTP esterne (Net::HTTP) per rilevare quelle lente nella finestra della
      # richiesta. Il patch è no-op (chiama super) se la detection è OFF → overhead trascurabile.
      initializer "closeyourit.instrument_net_http" do
        require "net/http"
        ::Net::HTTP.prepend(CloseYourIt::Rails::NetHTTPPatch) unless ::Net::HTTP.ancestors.include?(CloseYourIt::Rails::NetHTTPPatch)
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

      # Broadcast opt-in di Rails.logger → CloseYourIt.log (config.capture_rails_logs, default OFF).
      # Spedisce solo i log dell'app ≥ logs_min_level. Richiede BroadcastLogger (Rails 7.1+).
      # `after: :load_config_initializers`: config.capture_rails_logs è impostato in
      # config/initializers/closeyourit.rb (CloseYourIt.init), che gira DOPO gli initializer dei
      # railtie. Senza questo `after:` il check leggerebbe il default (false) e il broadcast non
      # verrebbe mai agganciato → i log dell'app non arriverebbero a CloseYourIt.
      initializer "closeyourit.capture_rails_logs", after: :load_config_initializers do
        config = CloseYourIt.configuration
        if config.capture_rails_logs && ::Rails.logger.respond_to?(:broadcast_to)
          ::Rails.logger.broadcast_to(CloseYourIt::Rails::LogBroadcast.new(config.logs_min_level))
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
