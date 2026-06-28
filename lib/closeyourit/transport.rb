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
    # Net::HTTP non segue i redirect: l'host canonico può rispondere 301 (es. apex → www).
    # Ri-POSTiamo a Location preservando metodo + body, così l'evento non si perde in silenzio.
    MAX_REDIRECTS = 2

    def initialize(configuration)
      @configuration = configuration
    end

    def send_event(payload, path:)
      response = post(payload, path)
      if response.is_a?(Net::HTTPSuccess)
        CloseYourIt.stats.increment(:sent)
      else
        CloseYourIt.stats.increment(:failed)
        CloseYourIt.logger.warn("CloseYourIt transport: HTTP #{response.code} su #{path}")
      end
      response
    rescue StandardError => e
      CloseYourIt.stats.increment(:failed)
      CloseYourIt.logger.error("CloseYourIt transport: #{e.class}: #{e.message}")
      nil
    end

    private

    def post(payload, path)
      body = JSON.generate(payload)
      uri = URI.parse("#{base_url}#{path}")
      redirects = 0

      loop do
        response = post_once(uri, body)
        location = response["location"] if response.is_a?(Net::HTTPRedirection)
        return response unless location && redirects < MAX_REDIRECTS

        redirects += 1
        uri = redirect_uri(uri, location)
      end
    end

    def post_once(uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@configuration.token}"
      request["Content-Type"] = "application/json"
      request["User-Agent"] = "closeyourit-ruby/#{VERSION}"
      request.body = body

      http.request(request)
    end

    # Location può essere assoluto (https://www.…) o relativo (/api/…): risolvilo sull'URI corrente.
    def redirect_uri(current, location)
      target = URI.parse(location)
      target.relative? ? current + target : target
    end

    def base_url
      @configuration.endpoint_url.to_s.chomp("/")
    end
  end
end
