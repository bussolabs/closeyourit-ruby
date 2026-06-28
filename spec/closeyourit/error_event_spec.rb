# frozen_string_literal: true

RSpec.describe CloseYourIt::ErrorEvent do
  let(:config) do
    CloseYourIt::Configuration.new.tap do |c|
      c.environment = "test"
      c.project_id = "proj-1"
    end
  end

  # Solleva dentro un rescue: Ruby imposta automaticamente `cause`.
  def exception_with_cause
    begin
      raise ArgumentError, "root cause"
    rescue ArgumentError
      raise RuntimeError, "outer message"
    end
  rescue RuntimeError => e
    e
  end

  subject(:payload) { described_class.from_exception(exception_with_cause, configuration: config).to_h }

  it "ha il formato evento Sentry (event_id hex32, level, timestamp, platform)" do
    expect(payload["level"]).to eq("error")
    expect(payload["platform"]).to eq("ruby")
    expect(payload["environment"]).to eq("test")
    expect(payload["event_id"]).to match(/\A[0-9a-f]{32}\z/)
    expect(payload["timestamp"]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    expect(payload["sdk"]).to include("name" => "closeyourit-ruby")
  end

  it "include il trace_id dello scope corrente (correlazione coi log)" do
    CloseYourIt::Scope.current.trace_id = "trace-9"
    event = described_class.from_exception(StandardError.new("x"), configuration: config).to_h
    expect(event["trace_id"]).to eq("trace-9")
  ensure
    CloseYourIt.clear_scope
  end

  it "mette l'eccezione principale come ULTIMA di exception.values" do
    main = payload["exception"]["values"].last
    expect(main["type"]).to eq("RuntimeError")
    expect(main["value"]).to eq("outer message")
    expect(main["mechanism"]).to eq("type" => "ruby", "handled" => false)
  end

  it "ha frame Sentry con filename/function/lineno/in_app" do
    frame = payload["exception"]["values"].last["stacktrace"]["frames"].first
    expect(frame.keys).to include("filename", "function", "lineno", "in_app")
  end

  it "include la cause-chain in values (causa per prima, principale per ultima)" do
    types = payload["exception"]["values"].map { |value| value["type"] }
    expect(types).to eq(%w[ArgumentError RuntimeError])
  end

  it "instrada verso il path /events" do
    event = described_class.from_exception(exception_with_cause, configuration: config)
    expect(event.ingest_path("proj-1")).to eq("/api/v1/projects/proj-1/events")
  end
end
