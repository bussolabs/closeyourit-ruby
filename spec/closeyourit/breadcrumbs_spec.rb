# frozen_string_literal: true

RSpec.describe "Breadcrumbs" do
  def enable!(**over)
    CloseYourIt.init do |c|
      c.endpoint_url = "https://closeyour.it"
      c.token = "tok"
      c.project_id = "proj-1"
      c.async_threads = 0
      over.each { |key, value| c.public_send("#{key}=", value) }
    end
  end

  describe CloseYourIt::BreadcrumbBuffer do
    it "accumula in ordine FIFO" do
      buffer = described_class.new(10)
      buffer.add(CloseYourIt::Breadcrumb.new(message: "a"))
      buffer.add(CloseYourIt::Breadcrumb.new(message: "b"))
      expect(buffer.to_a.map { |c| c["message"] }).to eq(%w[a b])
    end

    it "droppa il più vecchio oltre la capacità (ring bounded)" do
      buffer = described_class.new(2)
      buffer.add(CloseYourIt::Breadcrumb.new(message: "a"))
      buffer.add(CloseYourIt::Breadcrumb.new(message: "b"))
      buffer.add(CloseYourIt::Breadcrumb.new(message: "c"))
      expect(buffer.to_a.map { |c| c["message"] }).to eq(%w[b c])
      expect(buffer.size).to eq(2)
    end

    it "con capacità 0 non accumula nulla" do
      buffer = described_class.new(0)
      buffer.add(CloseYourIt::Breadcrumb.new(message: "a"))
      expect(buffer).to be_empty
    end

    it "con capacità negativa è no-op (size/empty?)" do
      buffer = described_class.new(-3)
      buffer.add(CloseYourIt::Breadcrumb.new(message: "a"))
      expect(buffer).to be_empty
      expect(buffer.size).to eq(0)
    end

    it "to_a serializza le briciole in hash" do
      buffer = described_class.new(5)
      buffer.add(CloseYourIt::Breadcrumb.new(message: "a", category: "ui"))
      expect(buffer.to_a).to all(be_a(Hash))
      expect(buffer.to_a.first).to include("message" => "a", "category" => "ui")
    end
  end

  describe CloseYourIt::Breadcrumb do
    it "ha la forma Sentry e omette data vuoto" do
      crumb = described_class.new(message: "hi", category: "query", level: "info").to_h
      expect(crumb).to include("timestamp", "type" => "default", "category" => "query",
                               "level" => "info", "message" => "hi")
      expect(crumb).not_to have_key("data")
    end

    it "mantiene data valorizzato e rispetta type/level/timestamp custom" do
      crumb = described_class.new(
        message: "click", type: "user", level: "warning",
        timestamp: "2026-01-01T00:00:00Z", data: { "x" => 1 }
      ).to_h
      expect(crumb).to include("type" => "user", "level" => "warning",
                               "timestamp" => "2026-01-01T00:00:00Z", "data" => { "x" => 1 })
    end

    it "omette le chiavi nil (es. category assente)" do
      crumb = described_class.new(message: "hi").to_h
      expect(crumb).not_to have_key("category")
    end
  end

  describe "CloseYourIt.add_breadcrumb" do
    it "popola lo scope corrente" do
      enable!
      CloseYourIt.add_breadcrumb(message: "navigated", category: "ui")
      expect(CloseYourIt::Scope.current.breadcrumbs.to_a.first).to include("message" => "navigated")
    end

    it "scruba le chiavi sensibili in data" do
      enable!
      CloseYourIt.add_breadcrumb(message: "login", data: { "email" => "a@b.com", "password" => "x" })
      data = CloseYourIt::Scope.current.breadcrumbs.to_a.first["data"]
      expect(data["password"]).to eq("[FILTERED]")
    end

    it "è no-op quando breadcrumbs_enabled è false" do
      enable!(breadcrumbs_enabled: false)
      CloseYourIt.add_breadcrumb(message: "x")
      expect(CloseYourIt::Scope.current.breadcrumbs).to be_empty
    end
  end

  describe "allegato all'evento errore" do
    let(:config) do
      CloseYourIt::Configuration.new.tap { |c| c.environment = "test"; c.project_id = "proj-1" }
    end

    def boom
      raise "boom"
    rescue RuntimeError => e
      e
    end

    it "include breadcrumbs.values nel payload" do
      enable!
      CloseYourIt.add_breadcrumb(message: "before crash", category: "query")
      payload = CloseYourIt::ErrorEvent.from_exception(boom, configuration: config).to_h

      values = payload.dig("breadcrumbs", "values")
      expect(values.first).to include("message" => "before crash", "category" => "query")
    ensure
      CloseYourIt.clear_scope
    end
  end

  describe CloseYourIt::Subscribers::SlowQuery, "#breadcrumb" do
    subject(:subscriber) { described_class.new }

    it "registra un breadcrumb con SQL offuscato (no literal)" do
      enable!
      subscriber.breadcrumb(name: "User Load", sql: "SELECT * FROM users WHERE email = 'a@b.com'",
                            duration_ms: 12.0)
      crumb = CloseYourIt::Scope.current.breadcrumbs.to_a.first
      expect(crumb["category"]).to eq("query")
      expect(crumb["message"]).to eq("SELECT * FROM users WHERE email = ?")
      expect(crumb["data"]).to include("name" => "User Load")
    end

    it "salta le query di sistema (SCHEMA/CACHE/TRANSACTION)" do
      enable!
      subscriber.breadcrumb(name: "SCHEMA", sql: "SELECT 1", duration_ms: 1.0)
      expect(CloseYourIt::Scope.current.breadcrumbs).to be_empty
    end
  end
end
