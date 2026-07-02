# frozen_string_literal: true

module CloseYourIt
  # Cache in-process delle righe dei file sorgente, per le context lines dei frame
  # (pre_context/context_line/post_context). Bounded: oltre MAX_FILES si svuota per intero —
  # semplice e sufficiente (i file di un'app in errore sono pochi e ricorrenti). Thread-safe.
  module LineCache
    MAX_FILES = 200

    @cache = {}
    @mutex = Mutex.new

    class << self
      # Righe del file (chomp-ate), oppure nil se non leggibile o path sintetico ("(eval)", "(irb)").
      def lines(path)
        return nil if path.nil? || path.empty? || path.start_with?("(")

        @mutex.synchronize do
          return @cache[path] if @cache.key?(path)

          @cache.clear if @cache.size >= MAX_FILES
          @cache[path] = read_lines(path)
        end
      end

      def clear
        @mutex.synchronize { @cache.clear }
      end

      private

      def read_lines(path)
        return nil unless File.readable?(path)

        File.readlines(path, chomp: true)
      rescue StandardError
        nil
      end
    end
  end
end
