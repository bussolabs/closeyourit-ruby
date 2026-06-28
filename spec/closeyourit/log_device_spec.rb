# frozen_string_literal: true

require "logger"

RSpec.describe CloseYourIt::LogDevice do
  subject(:logger) { described_class.new }

  before do
    allow(CloseYourIt).to receive(:log)
    allow(CloseYourIt).to receive(:logs_active?).and_return(true)
  end

  it "info inoltra il livello info con gli attributes" do
    logger.info("hi", user_id: 1)
    expect(CloseYourIt).to have_received(:log).with("info", "hi", user_id: 1)
  end

  it "warn mappa sul livello warning (enum backend)" do
    logger.warn("careful")
    expect(CloseYourIt).to have_received(:log).with("warning", "careful")
  end

  it "debug/error/fatal inoltrano il rispettivo livello" do
    logger.debug("d")
    logger.error("e")
    logger.fatal("f")
    expect(CloseYourIt).to have_received(:log).with("debug", "d")
    expect(CloseYourIt).to have_received(:log).with("error", "e")
    expect(CloseYourIt).to have_received(:log).with("fatal", "f")
  end

  it "<< inoltra come info" do
    logger << "streamed"
    expect(CloseYourIt).to have_received(:log).with("info", "streamed")
  end

  it "add mappa la severità numerica (::Logger::ERROR → error)" do
    logger.add(::Logger::ERROR, "boom")
    expect(CloseYourIt).to have_received(:log).with("error", "boom")
  end

  it "valuta il block come messaggio" do
    logger.info { "lazy" }
    expect(CloseYourIt).to have_received(:log).with("info", "lazy")
  end

  it "NON valuta il block quando i log sono spenti (lazy)" do
    allow(CloseYourIt).to receive(:logs_active?).and_return(false)
    evaluated = false
    logger.debug { evaluated = true }
    expect(evaluated).to be(false)
    expect(CloseYourIt).not_to have_received(:log)
  end
end
