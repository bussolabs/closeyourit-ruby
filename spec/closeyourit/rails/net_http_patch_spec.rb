# frozen_string_literal: true

RSpec.describe CloseYourIt::Rails::NetHTTPPatch do
  # Classe finta che simula Net::HTTP: `address` (host) + `request` (round-trip). Il patch è prepended
  # → intercetta `request`, cronometra, e spinge la chiamata nel profilo dello Scope corrente.
  let(:http_class) do
    Class.new do
      def initialize(address) = @address = address
      attr_reader :address
      def request(_req, _body = nil) = :response
      prepend CloseYourIt::Rails::NetHTTPPatch
    end
  end

  def enable!(**over)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.detect_performance_issues = true
      c.capture_external_http = true
      over.each { |k, v| c.public_send("#{k}=", v) }
    end
  end

  before { CloseYourIt::Scope.reset! }
  after { CloseYourIt::Scope.reset! }

  let(:req) { double("request", path: "/v1/charges/ch_12345") }

  it "registra la chiamata esterna nel profilo (host + path templatizzato)" do
    enable!
    http_class.new("api.stripe.com").request(req)
    calls = CloseYourIt::Scope.current.performance_profile.external_calls
    expect(calls.size).to eq(1)
    expect(calls.first[:host]).to eq("api.stripe.com")
    expect(calls.first[:path]).to eq("/v1/charges/ch_<n>")
    expect(calls.first[:duration_ms]).to be >= 0
  end

  it "restituisce la risposta originale (trasparente)" do
    enable!
    expect(http_class.new("api.stripe.com").request(req)).to eq(:response)
  end

  it "esclude le chiamate verso l'endpoint CloseYourIt (niente loop sulla telemetria)" do
    enable!
    http_class.new("closeyour.it").request(req)
    expect(CloseYourIt::Scope.current.performance_profile.external_calls).to be_empty
  end

  it "no-op se detect_performance_issues è OFF" do
    enable!(detect_performance_issues: false)
    http_class.new("api.stripe.com").request(req)
    expect(CloseYourIt::Scope.current.performance_profile.external_calls).to be_empty
  end
end
