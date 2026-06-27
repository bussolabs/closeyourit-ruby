# frozen_string_literal: true

module CloseYourIt
  module Rails
    # Incluso in ActiveJob::Base (via railtie `on_load(:active_job)`): cattura gli errori dei job
    # (oggi persi) con il contesto del job, poi ri-solleva. La logica vive in `.monitor` per essere
    # testabile senza ActiveSupport/ActiveJob.
    module ActiveJobExtension
      def self.included(base)
        base.around_perform do |job, block|
          CloseYourIt::Rails::ActiveJobExtension.monitor(job) { block.call }
        end
      end

      # Esegue il job arricchendo lo scope con tag/context; cattura l'errore (handled:false) e
      # ri-solleva; resetta lo scope a fine job (no bleed tra job sullo stesso thread).
      def self.monitor(job)
        return yield unless CloseYourIt.configuration.report_active_job_errors

        begin
          apply_job_scope(job)
          yield
        rescue Exception => e # rubocop:disable Lint/RescueException
          CloseYourIt.capture_exception(e, handled: false)
          raise
        ensure
          CloseYourIt::Scope.reset!
        end
      end

      def self.apply_job_scope(job)
        CloseYourIt.set_tag("job.class", job.class.name)
        CloseYourIt.set_tag("job.queue", job.queue_name) if job.respond_to?(:queue_name)

        context = {}
        context["job_id"] = job.job_id if job.respond_to?(:job_id)
        context["executions"] = job.executions if job.respond_to?(:executions)
        CloseYourIt.set_context("active_job", context) unless context.empty?
      end
    end
  end
end
