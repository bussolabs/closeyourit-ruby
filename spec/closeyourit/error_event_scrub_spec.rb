# frozen_string_literal: true

RSpec.describe "ErrorEvent — scrub del messaggio" do
  it "redige il value (in exception.values) secondo scrub_message_patterns" do
    config = CloseYourIt::Configuration.new
    config.scrub_message_patterns = [ /token=\w+/ ]

    exception =
      begin
        raise "auth failed token=abc123"
      rescue StandardError => e
        e
      end

    payload = CloseYourIt::ErrorEvent.from_exception(exception, configuration: config).to_h
    expect(payload["exception"]["values"].last["value"]).to eq("auth failed [FILTERED]")
  end
end
