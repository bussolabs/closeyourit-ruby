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
        !body.key?("arguments")
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
      body["kind"] == "slow_method" && body["label"].include?("compute") && !body.key?("arguments")
    }
  end

  it "preserva il blocco passato al metodo e non invia sotto soglia" do
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.slow_method_threshold_ms = 1_000_000
    end
    stub = stub_request(:post, url)

    klass = Class.new do
      include CloseYourIt::Monitor
      def each_double(values, &block) = values.map(&block)
      monitor :each_double
    end

    expect(klass.new.each_double([ 1, 2 ]) { |n| n * 2 }).to eq([ 2, 4 ])
    expect(stub).not_to have_been_requested
  end

  it "include arguments (posizionali + kwargs scrubbed) quando capture_method_arguments è ON" do
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.slow_method_threshold_ms = 0
      c.capture_method_arguments = true
    end
    stub_request(:post, url)

    klass = Class.new do
      include CloseYourIt::Monitor
      def run(period, password:) = [ period, password ]
      monitor :run
    end

    klass.new.run("daily", password: "secret")

    expect(WebMock).to have_requested(:post, url).with { |req|
      JSON.parse(req.body)["arguments"] == [
        { "name" => "arg1", "value" => "\"daily\"" },
        { "name" => "password", "value" => "[FILTERED]" }
      ]
    }
  end
end
