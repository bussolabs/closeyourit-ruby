# frozen_string_literal: true

RSpec.describe CloseYourIt::Scrubber do
  def scrubber(**over)
    config = CloseYourIt::Configuration.new
    over.each { |k, v| config.public_send("#{k}=", v) }
    described_class.new(config)
  end

  describe "#filter_params" do
    it "redige le chiavi sensibili (denylist) anche annidate" do
      out = scrubber.filter_params(
        "name" => "Mario",
        "password" => "p",
        "nested" => { "api_key" => "x", "ok" => 1 }
      )
      expect(out).to eq(
        "name" => "Mario",
        "password" => "[FILTERED]",
        "nested" => { "api_key" => "[FILTERED]", "ok" => 1 }
      )
    end

    it "redige Authorization e Cookie" do
      out = scrubber.filter_params("Authorization" => "Bearer x", "Cookie" => "a=b")
      expect(out.values).to all(eq("[FILTERED]"))
    end

    it "rispetta filter_parameters custom (stringa e regexp)" do
      out = scrubber(filter_parameters: [ "pin", /\Asegreto/ ]).filter_params(
        "user_pin" => "1234", "segreto_x" => "y", "altro" => "z"
      )
      expect(out).to eq("user_pin" => "[FILTERED]", "segreto_x" => "[FILTERED]", "altro" => "z")
    end

    it "filtra dentro gli array" do
      out = scrubber.filter_params([ { "token" => "t" }, { "ok" => 1 } ])
      expect(out).to eq([ { "token" => "[FILTERED]" }, { "ok" => 1 } ])
    end
  end

  describe "#obfuscate_sql" do
    it "maschera literal stringa e numerici quando attivo" do
      sql = "SELECT * FROM users WHERE email = 'a@b.com' AND age = 42"
      out = scrubber(obfuscate_sql: true).obfuscate_sql(sql)
      expect(out).not_to include("a@b.com")
      expect(out).not_to include("42")
      expect(out).to include("SELECT", "FROM users", "WHERE email =")
    end

    it "passthrough quando disattivato" do
      expect(scrubber(obfuscate_sql: false).obfuscate_sql("SELECT 1")).to eq("SELECT 1")
    end
  end

  describe "#scrub_message" do
    it "applica gli scrub_message_patterns" do
      out = scrubber(scrub_message_patterns: [ /secret-\d+/ ]).scrub_message("leaked secret-123 here")
      expect(out).to eq("leaked [FILTERED] here")
    end

    it "ritorna il messaggio invariato senza pattern" do
      expect(scrubber.scrub_message("hello")).to eq("hello")
    end
  end
end
