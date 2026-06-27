# frozen_string_literal: true

RSpec.describe CloseYourIt::Subscribers::SlowQuery do
  let(:url) { "https://closeyour.it/api/v1/projects/proj-1/metrics" }

  def enable!(threshold: 100)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.slow_query_threshold_ms = threshold
    end
  end

  def record(**over)
    defaults = { name: "User Load", duration_ms: 150, sql: "SELECT 1", cached: false }
    described_class.new.record(**defaults.merge(over))
  end

  it "non invia sotto soglia (X-1)" do
    enable!(threshold: 100)
    stub = stub_request(:post, url)
    record(duration_ms: 99)
    expect(stub).not_to have_been_requested
  end

  it "invia a soglia esatta (X)" do
    enable!(threshold: 100)
    stub = stub_request(:post, url)
    record(duration_ms: 100)
    expect(stub).to have_been_requested.times(1)
  end

  it "invia sopra soglia (X+1) sul path /metrics" do
    enable!(threshold: 100)
    stub = stub_request(:post, url)
    record(duration_ms: 101)
    expect(stub).to have_been_requested.times(1)
  end

  it "ignora SCHEMA e CACHE anche se lentissime" do
    enable!(threshold: 1)
    stub = stub_request(:post, url)
    record(name: "SCHEMA", duration_ms: 999)
    record(name: "CACHE", duration_ms: 999)
    expect(stub).not_to have_been_requested
  end

  it "compone slow_query con sample_id, SQL offuscato, db_system e senza binds" do
    enable!(threshold: 1)
    stub_request(:post, url)
    connection = double("connection", adapter_name: "PostgreSQL")

    record(
      name: "User Load",
      duration_ms: 50,
      sql: "SELECT * FROM users WHERE email = 'a@b.com'",
      cached: true,
      connection: connection
    )

    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body)
      body["kind"] == "slow_query" &&
        body["sample_id"].is_a?(String) &&
        body["name"] == "User Load" &&
        body["cached"] == true &&
        body["db_system"] == "postgresql" &&
        !body["sql"].include?("a@b.com") &&
        !body.key?("binds")
    }
  end

  it "include la source (call-site) sempre, anche con cattura bind OFF" do
    enable!(threshold: 1)
    stub_request(:post, url)

    record(duration_ms: 50, source: "app/models/order.rb:42")

    expect(WebMock).to have_requested(:post, url).with { |req|
      JSON.parse(req.body)["source"] == "app/models/order.rb:42"
    }
  end

  it "NON include bindings se capture_query_bindings è OFF (default privacy)" do
    enable!(threshold: 1)
    stub_request(:post, url)
    attr = double("attr", name: "email")

    record(duration_ms: 50, binds: [ attr ], type_casted_binds: [ "a@b.com" ])

    expect(WebMock).to have_requested(:post, url).with { |req|
      !JSON.parse(req.body).key?("bindings")
    }
  end

  it "include bindings (scrubbed per colonna) quando capture_query_bindings è ON" do
    enable!(threshold: 1)
    CloseYourIt.configuration.capture_query_bindings = true
    stub_request(:post, url)
    order = double("attr", name: "order_id")
    pw = double("attr", name: "password")

    record(duration_ms: 50, binds: [ order, pw ], type_casted_binds: [ 42, "secret" ])

    expect(WebMock).to have_requested(:post, url).with { |req|
      JSON.parse(req.body)["bindings"] == [
        { "name" => "order_id", "value" => "42" },
        { "name" => "password", "value" => "[FILTERED]" }
      ]
    }
  end
end
