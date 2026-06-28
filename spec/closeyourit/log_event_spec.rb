# frozen_string_literal: true

RSpec.describe CloseYourIt::LogEvent do
  def config
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.environment = "production"
      c.release = "v1.2"
    end
    CloseYourIt.configuration
  end

  after { CloseYourIt.clear_scope }

  it "produce il payload log con tutti i campi" do
    event = described_class.new("hello", level: :warning, attributes: { user_id: 9 },
                                logger: "system", configuration: config)
    payload = event.to_h
    expect(payload["level"]).to eq("warning")
    expect(payload["message"]).to eq("hello")
    expect(payload["attributes"]).to eq("user_id" => 9)
    expect(payload["logger"]).to eq("system")
    expect(payload["environment"]).to eq("production")
    expect(payload["release"]).to eq("v1.2")
    expect(payload["event_id"]).to be_a(String)
    expect(payload["sdk"]["name"]).to eq("closeyourit-ruby")
  end

  it "normalizza il livello ai valori canonici del backend (anche se costruito direttamente)" do
    expect(described_class.new("x", level: :warn, attributes: {}, configuration: config).to_h["level"]).to eq("warning")
    expect(described_class.new("x", level: "ERROR", attributes: {}, configuration: config).to_h["level"]).to eq("error")
    expect(described_class.new("x", level: :verbose, attributes: {}, configuration: config).to_h["level"]).to eq("info")
  end

  it "normalizza gli alias err/unknown" do
    expect(described_class.new("x", level: :err, attributes: {}, configuration: config).to_h["level"]).to eq("error")
    expect(described_class.new("x", level: :unknown, attributes: {}, configuration: config).to_h["level"]).to eq("fatal")
  end

  it "scruba le chiavi sensibili dentro array annidati negli attributes" do
    event = described_class.new("x", level: :info,
                                attributes: { items: [ { token: "t", ok: "v" } ] }, configuration: config)
    expect(event.to_h["attributes"]["items"]).to eq([ { "token" => "[FILTERED]", "ok" => "v" } ])
  end

  it "ingest_path punta a /logs" do
    event = described_class.new("x", level: :info, attributes: {}, configuration: config)
    expect(event.ingest_path("p1")).to eq("/api/v1/projects/p1/logs")
  end

  it "scruba gli attributes sensibili (ricorsivo)" do
    event = described_class.new("x", level: :info,
                                attributes: { password: "hunter2", nested: { token: "k", ok: "v" } },
                                configuration: config)
    data = event.to_h["attributes"]
    expect(data["password"]).to eq("[FILTERED]")
    expect(data["nested"]).to eq("token" => "[FILTERED]", "ok" => "v")
  end

  it "include il trace_id dallo scope corrente (correlazione)" do
    config
    CloseYourIt::Scope.current.trace_id = "trace-1"
    event = described_class.new("x", level: :info, attributes: {}, configuration: CloseYourIt.configuration)
    expect(event.to_h["trace_id"]).to eq("trace-1")
  end

  it "omette trace_id e logger se assenti (compact)" do
    payload = described_class.new("x", level: :info, attributes: {}, configuration: config).to_h
    expect(payload).not_to have_key("trace_id")
    expect(payload).not_to have_key("logger")
  end
end
