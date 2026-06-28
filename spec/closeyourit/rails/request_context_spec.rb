# frozen_string_literal: true

RSpec.describe CloseYourIt::Rails::RequestContext do
  def enable!(**over)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      over.each { |key, value| c.public_send("#{key}=", value) }
    end
  end

  let(:env) do
    {
      "REQUEST_METHOD"     => "GET",
      "rack.url_scheme"    => "https",
      "HTTP_HOST"          => "app.test",
      "PATH_INFO"          => "/orders/42",
      "QUERY_STRING"       => "token=secret&page=2",
      "REMOTE_ADDR"        => "1.2.3.4",
      "HTTP_ACCEPT"        => "text/html",
      "HTTP_USER_AGENT"    => "RSpec",
      "HTTP_AUTHORIZATION" => "Bearer hunter2",
      "HTTP_COOKIE"        => "session=abc"
    }
  end

  def capture_request_via(app_env)
    captured = :unset
    app = lambda do |_e|
      captured = CloseYourIt::Scope.current.request
      [ 200, {}, [] ]
    end
    described_class.new(app).call(app_env)
    captured
  end

  it "popola lo scope con method/url/header allowlist durante la richiesta" do
    enable!
    request = capture_request_via(env)

    expect(request["method"]).to eq("GET")
    expect(request["url"]).to eq("https://app.test/orders/42")
    expect(request["headers"]).to include("Accept" => "text/html", "User-Agent" => "RSpec")
  end

  it "non include mai header sensibili (Authorization/Cookie)" do
    enable!
    request = capture_request_via(env)
    expect(request["headers"].keys).not_to include("Authorization", "Cookie")
  end

  it "non include l'URL con la query string (PII potenziale)" do
    enable!
    request = capture_request_via(env)
    expect(request["url"]).not_to include("token=secret")
  end

  it "esclude query_string e IP quando send_pii è false" do
    enable!(send_pii: false)
    request = capture_request_via(env)
    expect(request).not_to have_key("query_string")
    expect(request).not_to have_key("env")
  end

  it "include query_string e IP quando send_pii è true" do
    enable!(send_pii: true)
    request = capture_request_via(env)
    expect(request["query_string"]).to eq("token=secret&page=2")
    expect(request["env"]).to eq("REMOTE_ADDR" => "1.2.3.4")
  end

  it "resetta lo scope a fine richiesta (ensure)" do
    enable!
    described_class.new(->(_e) { [ 200, {}, [] ] }).call(env)
    expect(CloseYourIt::Scope.current.to_event_hash).to eq({})
  end

  it "resetta lo scope anche se l'app solleva" do
    enable!
    app = ->(_e) { raise "boom" }
    expect { described_class.new(app).call(env) }.to raise_error("boom")
    expect(CloseYourIt::Scope.current.to_event_hash).to eq({})
  end

  it "non popola la request quando la gemma è disabilitata" do
    # nessun enable! → CloseYourIt.enabled? è false
    expect(capture_request_via(env)).to be_nil
  end

  it "non popola la request quando capture_request è false" do
    enable!(capture_request: false)
    expect(capture_request_via(env)).to be_nil
  end

  it "ritorna la risposta dell'app invariata" do
    enable!
    app = ->(_e) { [ 201, { "X" => "1" }, [ "body" ] ] }
    expect(described_class.new(app).call(env)).to eq([ 201, { "X" => "1" }, [ "body" ] ])
  end

  describe "trace_id (correlazione log↔errori)" do
    def capture_trace_via(app_env)
      captured = :unset
      app = lambda do |_e|
        captured = CloseYourIt::Scope.current.trace_id
        [ 200, {}, [] ]
      end
      described_class.new(app).call(app_env)
      captured
    end

    it "genera un trace_id durante la richiesta" do
      enable!
      expect(capture_trace_via(env)).to be_a(String)
    end

    it "riusa action_dispatch.request_id se presente" do
      enable!
      expect(capture_trace_via(env.merge("action_dispatch.request_id" => "req-123"))).to eq("req-123")
    end

    it "riusa X-Request-Id (prima voce) se presente" do
      enable!
      expect(capture_trace_via(env.merge("HTTP_X_REQUEST_ID" => "req-aaa, req-bbb"))).to eq("req-aaa")
    end

    it "non setta trace_id quando la gemma è disabilitata" do
      expect(capture_trace_via(env)).to be_nil
    end

    it "setta il trace_id anche con capture_request disabilitato (correlazione indipendente)" do
      enable!(capture_request: false)
      expect(capture_trace_via(env)).to be_a(String)
    end

    it "ripiega su SecureRandom se X-Request-Id è whitespace" do
      enable!
      expect(capture_trace_via(env.merge("HTTP_X_REQUEST_ID" => "   "))).to be_a(String)
    end
  end

  it "l'evento catturato durante la richiesta porta il request context" do
    enable!
    url = "https://closeyour.it/api/v1/projects/proj-1/events"
    stub_request(:post, url)
    app = ->(_e) { raise "kaboom" }

    stack = described_class.new(CloseYourIt::Rails::CaptureExceptions.new(app))
    expect { stack.call(env) }.to raise_error(RuntimeError, "kaboom")

    expect(WebMock).to have_requested(:post, url).with { |req|
      JSON.parse(req.body).dig("request", "method") == "GET"
    }
  end
end
