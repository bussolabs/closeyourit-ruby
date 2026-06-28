# frozen_string_literal: true

RSpec.describe "CloseYourIt.log (logging strutturato)" do
  let(:url) { "https://closeyour.it/api/v1/projects/proj-1/logs" }

  def enable!(**over)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.logs_batch_size = 2
      c.logs_flush_interval = 0 # niente timer nei test: flush solo a batch o manuale
      over.each { |key, value| c.public_send("#{key}=", value) }
    end
  end

  after { CloseYourIt.clear_scope }

  it "flusha a batch_size inviando un ARRAY a /logs" do
    enable! # batch_size 2
    stub = stub_request(:post, url)

    CloseYourIt.log(:info, "one")
    expect(stub).not_to have_been_requested # 1 < 2: non ancora

    CloseYourIt.log(:warning, "two")
    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body)
      body.is_a?(Array) && body.size == 2 &&
        body[0]["message"] == "one" && body[1]["level"] == "warning"
    }
  end

  it "il flush manuale invia ciò che è in buffer (sotto batch_size)" do
    enable!(logs_batch_size: 50)
    stub_request(:post, url)

    CloseYourIt.log(:info, "pending")
    CloseYourIt.flush_logs

    expect(WebMock).to have_requested(:post, url).with { |req| JSON.parse(req.body).first["message"] == "pending" }
  end

  it "include gli attributes scrubbati" do
    enable!(logs_batch_size: 1)
    stub_request(:post, url)

    CloseYourIt.log(:error, "boom", password: "x", ok: "v")

    expect(WebMock).to have_requested(:post, url).with { |req|
      JSON.parse(req.body).first["attributes"] == { "password" => "[FILTERED]", "ok" => "v" }
    }
  end

  it "è no-op quando la gemma è disabilitata" do
    stub = stub_request(:post, url)
    CloseYourIt.log(:info, "x")
    CloseYourIt.flush_logs
    expect(stub).not_to have_been_requested
  end

  it "rispetta logs_enabled = false" do
    enable!(logs_enabled: false, logs_batch_size: 1)
    stub = stub_request(:post, url)
    CloseYourIt.log(:info, "x")
    expect(stub).not_to have_been_requested
  end

  it "non spedisce con logs_sample_rate = 0" do
    enable!(logs_sample_rate: 0.0, logs_batch_size: 1)
    stub = stub_request(:post, url)
    CloseYourIt.log(:info, "x")
    expect(stub).not_to have_been_requested
  end

  it "normalizza il livello :warn a warning (evita il degrado a info lato backend)" do
    enable!(logs_batch_size: 1)
    stub_request(:post, url)
    CloseYourIt.log(:warn, "x")
    expect(WebMock).to have_requested(:post, url).with { |req| JSON.parse(req.body).first["level"] == "warning" }
  end

  it "supporta un logger esplicito separato dagli attributes" do
    enable!(logs_batch_size: 1)
    stub_request(:post, url)
    CloseYourIt.log(:info, "x", logger: "payments", k: "v")
    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body).first
      body["logger"] == "payments" && body["attributes"] == { "k" => "v" }
    }
  end
end
