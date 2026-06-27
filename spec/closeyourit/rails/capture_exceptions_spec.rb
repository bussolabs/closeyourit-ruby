# frozen_string_literal: true

RSpec.describe CloseYourIt::Rails::CaptureExceptions do
  let(:url) { "https://closeyour.it/api/v1/projects/proj-1/events" }

  def enable!
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
    end
  end

  it "ri-solleva l'eccezione e la cattura come evento Sentry (level=error)" do
    enable!
    stub = stub_request(:post, url)
    app = ->(_env) { raise "kaboom" }

    expect { described_class.new(app).call({}) }.to raise_error(RuntimeError, "kaboom")

    expect(stub).to have_been_requested.times(1)
    expect(WebMock).to have_requested(:post, url).with { |req| JSON.parse(req.body)["level"] == "error" }
  end

  it "lascia passare le risposte normali senza catturare" do
    app = ->(_env) { [ 200, {}, [ "ok" ] ] }

    expect(CloseYourIt).not_to receive(:capture_exception)
    expect(described_class.new(app).call({})).to eq([ 200, {}, [ "ok" ] ])
  end

  it "non invia le eccezioni escluse (es. RecordNotFound) ma le ri-solleva" do
    stub_const("ActiveRecord::RecordNotFound", Class.new(StandardError))
    enable!
    stub = stub_request(:post, url)
    app = ->(_env) { raise ActiveRecord::RecordNotFound, "missing" }

    expect { described_class.new(app).call({}) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(stub).not_to have_been_requested
  end
end
