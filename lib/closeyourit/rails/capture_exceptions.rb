# frozen_string_literal: true

module CloseYourIt
  module Rails
    # Rack middleware: cattura le eccezioni non gestite, le invia a CloseYourIt
    # e le **ri-solleva** (l'app continua a gestirle come prima). Rack puro, nessuna
    # dipendenza da Rails → testabile in isolamento.
    class CaptureExceptions
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue Exception => e # rubocop:disable Lint/RescueException
        CloseYourIt.capture_exception(e)
        raise
      end
    end
  end
end
