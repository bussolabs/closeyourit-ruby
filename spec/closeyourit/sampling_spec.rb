# frozen_string_literal: true

RSpec.describe "Sampling, ignore per Regexp e release detection" do
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

  def boom
    raise "boom"
  rescue RuntimeError => e
    e
  end

  describe "sample_rate" do
    it "0.0 non invia nulla (deterministico)" do
      enable!(sample_rate: 0.0)
      stub = stub_request(:post, url)
      CloseYourIt.capture_exception(boom)
      expect(stub).not_to have_been_requested
    end

    it "1.0 invia sempre (deterministico)" do
      enable!(sample_rate: 1.0)
      stub = stub_request(:post, url)
      CloseYourIt.capture_exception(boom)
      expect(stub).to have_been_requested
    end

    it "intermedio: invia quando Random.rand < rate" do
      enable!(sample_rate: 0.5)
      allow(Random).to receive(:rand).and_return(0.4)
      stub = stub_request(:post, url)
      CloseYourIt.capture_exception(boom)
      expect(stub).to have_been_requested
    end

    it "intermedio: droppa quando Random.rand >= rate" do
      enable!(sample_rate: 0.5)
      allow(Random).to receive(:rand).and_return(0.6)
      stub = stub_request(:post, url)
      CloseYourIt.capture_exception(boom)
      expect(stub).not_to have_been_requested
    end
  end

  describe "ignore eccezioni" do
    it "ignora per match Regexp sul nome classe" do
      stub_const("Payments::TimeoutError", Class.new(StandardError))
      enable!(excluded_exceptions: [ /Timeout/ ])
      stub = stub_request(:post, url)

      ex = (raise Payments::TimeoutError, "x" rescue $!) # rubocop:disable Style/RescueModifier
      CloseYourIt.capture_exception(ex)

      expect(stub).not_to have_been_requested
    end

    it "mantiene il match per stringa (retrocompatibile)" do
      stub_const("My::Err", Class.new(StandardError))
      enable!(excluded_exceptions: [ "My::Err" ])
      stub = stub_request(:post, url)

      ex = (raise My::Err, "x" rescue $!) # rubocop:disable Style/RescueModifier
      CloseYourIt.capture_exception(ex)

      expect(stub).not_to have_been_requested
    end

    it "invia le eccezioni non escluse" do
      enable!(excluded_exceptions: [ /Timeout/ ])
      stub = stub_request(:post, url)
      CloseYourIt.capture_exception(boom)
      expect(stub).to have_been_requested
    end
  end

  describe "Configuration#excluded_exceptions= preserva i Regexp" do
    subject(:config) { CloseYourIt::Configuration.new }

    it "converte Class/String a stringa e tiene i Regexp" do
      config.excluded_exceptions = [ RuntimeError, "My::Error", /Timeout/ ]
      expect(config.excluded_exceptions).to eq([ "RuntimeError", "My::Error", /Timeout/ ])
    end
  end

  describe "Configuration#detect_release" do
    subject(:config) { CloseYourIt::Configuration.new }

    it "usa KAMAL_VERSION quando presente" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("KAMAL_VERSION").and_return("v1.2.3")
      expect(config.detect_release).to eq("v1.2.3")
    end

    it "cade su git_revision quando le env sono assenti" do
      allow(ENV).to receive(:[]).and_call_original
      %w[KAMAL_VERSION GIT_SHA GIT_REVISION SOURCE_VERSION HEROKU_SLUG_COMMIT].each do |key|
        allow(ENV).to receive(:[]).with(key).and_return(nil)
      end
      allow(config).to receive(:git_revision).and_return("deadbee")
      expect(config.detect_release).to eq("deadbee")
    end
  end
end
