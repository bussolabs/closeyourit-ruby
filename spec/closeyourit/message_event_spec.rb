# frozen_string_literal: true

RSpec.describe "CloseYourIt.capture_message" do
  let(:url) { "https://closeyour.it/api/v1/projects/proj-1/events" }

  def enable!(**over)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      over.each { |key, value| c.public_send("#{key}=", value) }
    end
  end

  it "invia un evento message in formato Sentry (message.formatted + level)" do
    enable!
    stub = stub_request(:post, url)

    CloseYourIt.capture_message("disk almost full", level: "warning")

    expect(stub).to have_been_requested
    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body)
      body.dig("message", "formatted") == "disk almost full" &&
        body["level"] == "warning" &&
        body["platform"] == "ruby"
    }
  end

  it "usa level info di default" do
    enable!
    stub_request(:post, url)
    CloseYourIt.capture_message("hello")
    expect(WebMock).to have_requested(:post, url).with { |req| JSON.parse(req.body)["level"] == "info" }
  end

  it "fonde lo scope (tags/user) nel messaggio" do
    enable!
    stub_request(:post, url)
    CloseYourIt.set_tag(:area, "disk")

    CloseYourIt.capture_message("x")

    expect(WebMock).to have_requested(:post, url).with { |req| JSON.parse(req.body).dig("tags", "area") == "disk" }
  ensure
    CloseYourIt.clear_scope
  end

  it "applica before_send (può scartare il messaggio)" do
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      c.before_send = ->(_payload) { nil }
    end
    stub = stub_request(:post, url)

    CloseYourIt.capture_message("dropped")

    expect(stub).not_to have_been_requested
  end

  it "è no-op quando la gemma è disabilitata" do
    stub = stub_request(:post, url)
    CloseYourIt.capture_message("x")
    expect(stub).not_to have_been_requested
  end
end
