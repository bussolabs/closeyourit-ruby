# frozen_string_literal: true

RSpec.describe CloseYourIt::Transport do
  subject(:transport) { described_class.new(config) }

  let(:config) do
    CloseYourIt::Configuration.new.tap do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
    end
  end

  let(:path) { "/api/v1/projects/proj-1/events" }
  let(:url) { "https://closeyour.it#{path}" }

  it "POSTa al path indicato con Bearer token e body JSON" do
    stub = stub_request(:post, url)

    transport.send_event({ "level" => "error" }, path: path)

    expect(stub).to have_been_requested
    expect(WebMock).to have_requested(:post, url).with(
      headers: { "Authorization" => "Bearer tok", "Content-Type" => "application/json" },
      body: { "level" => "error" }.to_json
    )
  end

  it "instrada path diversi (errori vs metriche)" do
    metrics = "https://closeyour.it/api/v1/projects/proj-1/metrics"
    stub = stub_request(:post, metrics)

    transport.send_event({ "kind" => "slow_query" }, path: "/api/v1/projects/proj-1/metrics")

    expect(stub).to have_been_requested
  end

  it "non solleva su errore di rete e ritorna nil" do
    stub_request(:post, url).to_timeout
    allow(CloseYourIt.internal_logger).to receive(:error)

    result = nil
    expect { result = transport.send_event({ "level" => "error" }, path: path) }.not_to raise_error
    expect(result).to be_nil
  end

  it "incrementa stats.failed e logga su errore di rete" do
    stub_request(:post, url).to_timeout
    allow(CloseYourIt.internal_logger).to receive(:error)

    expect { transport.send_event({ "level" => "error" }, path: path) }
      .to change { CloseYourIt.stats[:failed] }.by(1)
    expect(CloseYourIt.internal_logger).to have_received(:error)
  end

  it "incrementa stats.sent su risposta 2xx" do
    stub_request(:post, url).to_return(status: 202)

    expect { transport.send_event({ "level" => "error" }, path: path) }
      .to change { CloseYourIt.stats[:sent] }.by(1)
  end

  it "logga a warn e incrementa stats.failed su status non-2xx" do
    stub_request(:post, url).to_return(status: 401)
    allow(CloseYourIt.internal_logger).to receive(:warn)

    expect { transport.send_event({ "level" => "error" }, path: path) }
      .to change { CloseYourIt.stats[:failed] }.by(1)
    expect(CloseYourIt.internal_logger).to have_received(:warn).with(/HTTP 401/)
  end

  it "segue il redirect apex → www preservando POST, body e Bearer" do
    www = "https://www.closeyour.it#{path}"
    stub_request(:post, url).to_return(status: 301, headers: { "Location" => www })
    final = stub_request(:post, www).to_return(status: 202, body: '{"id":"e1"}')

    transport.send_event({ "level" => "error" }, path: path)

    expect(final).to have_been_requested
    expect(WebMock).to have_requested(:post, www).with(
      headers: { "Authorization" => "Bearer tok", "Content-Type" => "application/json" },
      body: { "level" => "error" }.to_json
    )
  end

  it "si ferma dopo MAX_REDIRECTS — niente loop infinito su redirect ciclico" do
    www = "https://www.closeyour.it#{path}"
    stub_request(:post, url).to_return(status: 301, headers: { "Location" => www })
    stub_request(:post, www).to_return(status: 301, headers: { "Location" => url })
    allow(CloseYourIt.internal_logger).to receive(:warn)

    result = nil
    expect { result = transport.send_event({ "level" => "error" }, path: path) }.not_to raise_error
    expect(result).to be_a(Net::HTTPRedirection)
    expect(a_request(:post, www)).to have_been_made
  end
end
