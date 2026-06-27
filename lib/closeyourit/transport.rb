# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module CloseYourIt
  # Spedisce un payload a un path di ingest (errori → /events, metriche → /metrics) via HTTP POST
  # con `Authorization: Bearer`. Mai solleva: ogni errore di rete è loggato e ingoiato.
  class Transport
    OPEN_TIMEOUT = 2
    READ_TIMEOUT = 3

    def initialize(configuration)
      @configuration = configuration
    end

    def send_event(payload, path:)
      post(payload, path)
    rescue StandardError => e
      CloseYourIt.logger.error("CloseYourIt transport: #{e.class}: #{e.message}")
      nil
    end

    private

    def post(payload, path)
      uri = URI.parse("#{base_url}#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@configuration.token}"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "closeyourit-ruby/#{VERSION}"
      request.body = JSON.generate(payload)

      http.request(request)
    end

    def base_url
      @configuration.endpoint_url.to_s.chomp("/")
    end
  end
end
