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

  # R3 — il backend rifiuta un batch log oltre LOGS_MAX_BATCH (413 R413-LOG-002) scartando l'INTERA
  # richiesta. Il buffer è già stato drenato → quei log sarebbero persi. flush_logs deve spezzare i
  # payload in chunk ≤ limite e POSTare ciascuno separatamente; un flush ≤ limite resta un solo POST.
  describe "#flush_logs — chunking batch log (R3)" do
    let(:transport) { instance_double(CloseYourIt::Transport) }

    before do
      allow(CloseYourIt::Transport).to receive(:new).and_return(transport)
      allow(transport).to receive(:send_event)
    end

    def log_events(count)
      Array.new(count) do |i|
        instance_double(
          CloseYourIt::LogEvent,
          to_h: { "message" => "log-#{i}" },
          ingest_path: "/api/v1/projects/proj-1/logs"
        )
      end
    end

    it "spezza un flush di 1500 eventi in due POST da 1000 e 500" do
      sizes = []
      allow(transport).to receive(:send_event) { |payload, **| sizes << payload.size }

      client.flush_logs(log_events(1500))

      expect(transport).to have_received(:send_event).twice
      expect(sizes).to eq([ 1000, 500 ])
    end

    it "invia un singolo POST quando il flush è esattamente al limite (1000)" do
      client.flush_logs(log_events(1000))
      expect(transport).to have_received(:send_event).once
    end

    it "invia un singolo POST per un flush piccolo" do
      client.flush_logs(log_events(50))
      expect(transport).to have_received(:send_event).once
    end

    it "POSTa ogni chunk allo stesso path /logs" do
      client.flush_logs(log_events(1500))
      expect(transport).to have_received(:send_event)
        .with(anything, path: "/api/v1/projects/proj-1/logs").twice
    end

    it "non eccede mai il limite: 2500 eventi → chunk da 1000, 1000, 500" do
      sizes = []
      allow(transport).to receive(:send_event) { |payload, **| sizes << payload.size }

      client.flush_logs(log_events(2500))

      expect(sizes).to eq([ 1000, 1000, 500 ])
    end
  end
end
