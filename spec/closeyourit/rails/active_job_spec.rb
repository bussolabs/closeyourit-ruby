# frozen_string_literal: true

RSpec.describe CloseYourIt::Rails::ActiveJobExtension do
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

  # Job fittizio (no ActiveJob): risponde come un ActiveJob::Base reale.
  class DummyJob
    attr_reader :job_id, :executions, :queue_name

    def initialize
      @job_id = "j-1"
      @executions = 2
      @queue_name = "mailers"
    end
  end

  it "esegue il blocco e ritorna il suo valore in caso di successo" do
    enable!
    result = described_class.monitor(DummyJob.new) { 42 }
    expect(result).to eq(42)
  end

  it "cattura l'errore del job (handled:false) con tag job.* e lo ri-solleva" do
    enable!
    stub_request(:post, url)
    job = DummyJob.new

    expect { described_class.monitor(job) { raise "job boom" } }.to raise_error("job boom")

    expect(WebMock).to have_requested(:post, url).with { |req|
      body = JSON.parse(req.body)
      body.dig("tags", "job.class") == "DummyJob" &&
        body.dig("tags", "job.queue") == "mailers" &&
        body.dig("contexts", "active_job", "job_id") == "j-1" &&
        body.dig("exception", "values").last.dig("mechanism", "handled") == false
    }
  end

  it "resetta lo scope a fine job" do
    enable!
    described_class.monitor(DummyJob.new) { CloseYourIt.set_tag(:x, "1") }
    expect(CloseYourIt::Scope.current.to_event_hash).to eq({})
  end

  it "non cattura quando report_active_job_errors è false" do
    enable!(report_active_job_errors: false)
    stub = stub_request(:post, url)
    expect { described_class.monitor(DummyJob.new) { raise "x" } }.to raise_error("x")
    expect(stub).not_to have_been_requested
  end

  it "dedup: stessa istanza catturata da rack e job invia una sola volta" do
    enable!
    stub = stub_request(:post, url)
    shared = (raise "dup" rescue $!) # rubocop:disable Style/RescueModifier

    CloseYourIt.capture_exception(shared) # cattura "rack"
    expect { described_class.monitor(DummyJob.new) { raise shared } }.to raise_error(shared)

    expect(stub).to have_been_requested.once
  end
end
