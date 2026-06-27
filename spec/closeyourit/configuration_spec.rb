# frozen_string_literal: true

RSpec.describe CloseYourIt::Configuration do
  describe "CloseYourIt.init" do
    it "restituisce la configurazione e la memorizza" do
      returned = CloseYourIt.init do |c|
        c.endpoint_url = "https://closeyour.it"
        c.token = "tok_123"
        c.project_id = "proj-1"
      end

      expect(returned).to be_a(described_class)
      expect(CloseYourIt.configuration).to be(returned)
      expect(CloseYourIt.configuration.token).to eq("tok_123")
    end
  end

  describe "valori di default" do
    subject(:config) { described_class.new }

    it "esclude RoutingError e RecordNotFound" do
      expect(config.excluded_exceptions).to include(
        "ActionController::RoutingError",
        "ActiveRecord::RecordNotFound"
      )
    end

    it "ha PII off e SQL offuscato di default" do
      expect(config.send_pii).to be(false)
      expect(config.obfuscate_sql).to be(true)
    end

    it "ha le soglie slow di default" do
      expect(config.slow_query_threshold_ms).to eq(100)
      expect(config.slow_method_threshold_ms).to eq(200)
    end

    it "ha la cattura bind/argomenti OFF di default (opt-in privacy)" do
      expect(config.capture_query_bindings).to be(false)
      expect(config.capture_method_arguments).to be(false)
    end

    it "ha almeno un thread di background" do
      expect(config.async_threads).to be >= 1
    end
  end

  describe "#enabled? — no-op senza credenziali" do
    def config_with(**over)
      described_class.new.tap do |c|
        c.endpoint_url = "https://closeyour.it"
        c.token = "tok"
        c.project_id = "proj-1"
        over.each { |k, v| c.public_send("#{k}=", v) }
      end
    end

    it "è false senza token" do
      expect(config_with(token: nil).enabled?).to be(false)
    end

    it "è false senza endpoint_url" do
      expect(config_with(endpoint_url: nil).enabled?).to be(false)
    end

    it "è false senza project_id" do
      expect(config_with(project_id: nil).enabled?).to be(false)
    end

    it "è true con endpoint https + token + project_id" do
      expect(config_with.enabled?).to be(true)
    end
  end

  describe "HTTPS guard" do
    it "in production rifiuta http:// (no-op) e logga un warning" do
      fake_logger = instance_double(Logger, warn: nil)
      allow(CloseYourIt).to receive(:logger).and_return(fake_logger)

      config = CloseYourIt.init do |c|
        c.endpoint_url = "http://insecure.test"
        c.token = "tok"
        c.project_id = "proj-1"
        c.environment = "production"
      end

      expect(config.enabled?).to be(false)
      expect(fake_logger).to have_received(:warn).with(/http/i)
    end

    it "in development consente http:// (con warning)" do
      fake_logger = instance_double(Logger, warn: nil)
      allow(CloseYourIt).to receive(:logger).and_return(fake_logger)

      config = CloseYourIt.init do |c|
        c.endpoint_url = "http://localhost:3011"
        c.token = "tok"
        c.project_id = "proj-1"
        c.environment = "development"
      end

      expect(config.enabled?).to be(true)
      expect(fake_logger).to have_received(:warn).with(/http/i)
    end
  end

  describe "normalizzazione setter" do
    it "converte excluded_exceptions a stringhe" do
      config = described_class.new
      config.excluded_exceptions = [ RuntimeError, "My::Error" ]
      expect(config.excluded_exceptions).to eq(%w[RuntimeError My::Error])
    end
  end
end
