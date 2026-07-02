# frozen_string_literal: true

require "json"
require "uri"
require_relative "../scrubber"

module CloseYourIt
  module Rails
    # Estrae i params del body della richiesta (`request.data`) al momento dell'EVENTO — mai
    # eagerly a ogni richiesta (zero overhead sul percorso felice). Preferisce i params già
    # parsati da Rails/Rack presenti in env; ripiega sulla rilettura di rack.input (con rewind)
    # solo per JSON/form ≤ MAX_BODY_BYTES. Output sanitizzato (upload → "[FILE: …]", oggetti →
    # "[OBJECT: …]", stringhe troncate) e scrubbato con la stessa denylist del resto del client.
    module RequestBody
      MAX_BODY_BYTES = 65_536
      MAX_DEPTH = 8
      MAX_STRING = 1024

      FORM_TYPE = "application/x-www-form-urlencoded"
      JSON_TYPE = "application/json"

      class << self
        def extract(env)
          params = parsed_params(env) || raw_params(env)
          return nil if params.nil? || params.empty?

          Scrubber.new(CloseYourIt.configuration).filter_params(sanitize(params, 0))
        rescue StandardError
          nil
        end

        private

        # Params già parsati a monte (ActionDispatch o Rack): nessuna rilettura del body.
        def parsed_params(env)
          env["action_dispatch.request.request_parameters"] || env["rack.request.form_hash"]
        end

        def raw_params(env)
          raw = read_body(env)
          return nil if raw.nil? || raw.empty?

          case env["CONTENT_TYPE"].to_s.split(";").first.to_s.strip.downcase
          when JSON_TYPE
            value = JSON.parse(raw)
            value.is_a?(Hash) ? value : { "_json" => value }
          when FORM_TYPE
            # Fallback flat (stdlib): il percorso reale con nesting passa dai params già parsati.
            URI.decode_www_form(raw).to_h
          end
        rescue JSON::ParserError, ArgumentError
          nil
        end

        def read_body(env)
          input = env["rack.input"]
          return nil if input.nil?

          length = env["CONTENT_LENGTH"].to_i
          return nil if length <= 0 || length > MAX_BODY_BYTES

          input.rewind if input.respond_to?(:rewind)
          raw = input.read(MAX_BODY_BYTES)
          input.rewind if input.respond_to?(:rewind)
          raw
        end

        def sanitize(value, depth)
          return "[TRUNCATED]" if depth > MAX_DEPTH

          case value
          when Hash    then value.each_with_object({}) { |(key, val), acc| acc[key.to_s] = sanitize(val, depth + 1) }
          when Array   then value.map { |item| sanitize(item, depth + 1) }
          when String  then value.size > MAX_STRING ? "#{value[0, MAX_STRING]}…" : value
          when Numeric, true, false, nil then value
          else
            if value.respond_to?(:original_filename)
              "[FILE: #{value.original_filename}]"
            else
              "[OBJECT: #{value.class.name}]"
            end
          end
        end
      end
    end
  end
end
