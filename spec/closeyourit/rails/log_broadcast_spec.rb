# frozen_string_literal: true

require "logger"

RSpec.describe CloseYourIt::Rails::LogBroadcast do
  before { allow(CloseYourIt).to receive(:log) }

  it "inoltra i log >= soglia a CloseYourIt.log" do
    described_class.new(:warn).error("boom")
    expect(CloseYourIt).to have_received(:log).with("error", "boom")
  end

  it "scarta i log sotto soglia" do
    described_class.new(:warn).info("noise")
    expect(CloseYourIt).not_to have_received(:log)
  end

  it "warn mappa sul livello warning" do
    described_class.new(:debug).warn("careful")
    expect(CloseYourIt).to have_received(:log).with("warning", "careful")
  end
end
