# frozen_string_literal: true

module CloseYourIt
  # Rimozione PII dai payload: filtro chiavi sensibili, normalizzazione SQL, scrub messaggi.
  # Privacy-by-default — vedi PDR §9.
  class Scrubber
    FILTERED = "[FILTERED]"

    # Token di chiavi sempre redatti (match per sottostringa, normalizzato).
    DENYLIST = %w[
      password passwd secret token api_key apikey authorization
      cookie set-cookie csrf credit_card card cvv ssn iban
    ].freeze

    STRING_LITERAL = /'(?:[^']|'')*'/
    NUMERIC_LITERAL = /\b\d+(?:\.\d+)?\b/

    def initialize(configuration)
      @configuration = configuration
    end

    # Filtra ricorsivamente Hash/Array sostituendo i valori delle chiavi sensibili.
    def filter_params(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, val), acc|
          acc[key] = sensitive_key?(key) ? FILTERED : filter_params(val)
        end
      when Array
        value.map { |item| filter_params(item) }
      else
        value
      end
    end

    # Maschera i literal (stringa/numerici) nello SQL, preservando la struttura.
    def obfuscate_sql(sql)
      return sql if sql.nil? || !@configuration.obfuscate_sql

      sql.to_s.gsub(STRING_LITERAL, "?").gsub(NUMERIC_LITERAL, "?")
    end

    def scrub_message(message)
      return message if message.nil?

      @configuration.scrub_message_patterns.reduce(message.to_s) do |acc, pattern|
        acc.gsub(pattern, FILTERED)
      end
    end

    # Valore di un singolo bind/argomento: redatto se il nome (colonna/parametro) è sensibile.
    def filter_value(key, value)
      sensitive_key?(key) ? FILTERED : value
    end

    private

    def sensitive_key?(key)
      normalized = normalize(key)
      return true if DENYLIST.any? { |token| normalized.include?(normalize(token)) }

      @configuration.filter_parameters.any? do |param|
        param.is_a?(Regexp) ? param.match?(key.to_s) : normalized.include?(normalize(param))
      end
    end

    def normalize(value)
      value.to_s.downcase.gsub(/[^a-z0-9]/, "")
    end
  end
end
