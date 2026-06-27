# frozen_string_literal: true

RSpec.describe "CloseYourIt.measure" do
  let(:url) { "https://closeyour.it/api/v1/projects/proj-1/metrics" }

  def enable!(threshold:)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.slow_method_threshold_ms = threshold
    end
  end

  it "ritorna il valore del blocco" do
    enable!(threshold: 1_000_000)
    expect(CloseYourIt.measure("x") { 42 }).to eq(42)
  end

  it "invia slow_method sul path /metrics quando supera la soglia (senza args)" do
    enable!(threshold: 0)
    stub = stub_request(:post, url)

    CloseYourIt.measure("checkout.total") { :done }

    expect(stub).to have_been_requested.times(1)
    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body)
      body["kind"] == "slow_method" &&
        body["label"] == "checkout.total" &&
        body["sample_id"].is_a?(String) &&
        body.key?("duration_ms") &&
        !body.key?("args")
    }
  end

  it "non invia quando sotto soglia" do
    enable!(threshold: 1_000_000)
    stub = stub_request(:post, url)
    CloseYourIt.measure("fast") { 1 }
    expect(stub).not_to have_been_requested
  end

  it "ri-solleva l'eccezione del blocco" do
    enable!(threshold: 1_000_000)
    expect { CloseYourIt.measure("x") { raise "boom" } }.to raise_error("boom")
  end
end

RSpec.describe CloseYourIt::Monitor do
  let(:url) { "https://closeyour.it/api/v1/projects/proj-1/metrics" }

  it "wrappa il metodo preservando il valore di ritorno e invia slow_method" do
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.slow_method_threshold_ms = 0
    end
    stub_request(:post, url)

    klass = Class.new do
      include CloseYourIt::Monitor
      def compute(first, second) = first + second
      monitor :compute
    end

    expect(klass.new.compute(3, 4)).to eq(7)
    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body)
      body["kind"] == "slow_method" && body["label"].include?("compute") && !body.key?("args")
    }
  end
end
