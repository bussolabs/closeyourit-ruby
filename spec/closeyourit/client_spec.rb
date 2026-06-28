# frozen_string_literal: true

RSpec.describe CloseYourIt::Client do
  subject(:client) { described_class.new(config) }

  let(:config) do
    CloseYourIt::Configuration.new.tap do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0 # sincrono → l'HTTP avviene durante capture_event
    end
  end

  let(:event) do
    instance_double(
      CloseYourIt::ErrorEvent,
      to_h: { "level" => "error" },
      ingest_path: "/api/v1/projects/proj-1/events"
    )
  end

  it "spedisce il payload al path indicato dall'evento" do
    stub = stub_request(:post, "https://closeyour.it/api/v1/projects/proj-1/events")

    client.capture_event(event)

    expect(stub).to have_been_requested
    expect(WebMock).to have_requested(:post, "https://closeyour.it/api/v1/projects/proj-1/events")
      .with(body: { "level" => "error" }.to_json)
  end

  it "applica before_send e usa il payload trasformato" do
    config.before_send = ->(payload) { payload.merge("tagged" => true) }
    stub_request(:post, "https://closeyour.it/api/v1/projects/proj-1/events")

    result = client.capture_event(event)

    expect(result).to eq("level" => "error", "tagged" => true)
    expect(WebMock).to have_requested(:post, "https://closeyour.it/api/v1/projects/proj-1/events")
      .with(body: { "level" => "error", "tagged" => true }.to_json)
  end

  it "non spedisce nulla quando before_send ritorna nil" do
    config.before_send = ->(_payload) { nil }
    stub = stub_request(:post, "https://closeyour.it/api/v1/projects/proj-1/events")

    expect(client.capture_event(event)).to be_nil
    expect(stub).not_to have_been_requested
  end

  it "incrementa stats.enqueued quando l'evento viene accettato" do
    stub_request(:post, "https://closeyour.it/api/v1/projects/proj-1/events")

    expect { client.capture_event(event) }.to change { CloseYourIt.stats[:enqueued] }.by(1)
  end

  it "delega shutdown al worker" do
    expect { client.shutdown }.not_to raise_error
  end
end
