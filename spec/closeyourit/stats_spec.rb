# frozen_string_literal: true

RSpec.describe CloseYourIt::Stats do
  subject(:stats) { described_class.new }

  it "parte da zero su tutti i contatori" do
    expect(stats.to_h).to eq(enqueued: 0, dropped: 0, sent: 0, failed: 0)
  end

  it "incrementa e ritorna il nuovo valore" do
    expect(stats.increment(:sent)).to eq(1)
    expect(stats.increment(:sent)).to eq(2)
    expect(stats[:sent]).to eq(2)
  end

  it "tiene contatori indipendenti" do
    stats.increment(:enqueued)
    stats.increment(:failed)
    expect(stats.to_h).to eq(enqueued: 1, dropped: 0, sent: 0, failed: 1)
  end

  it "azzera con reset!" do
    stats.increment(:dropped)
    expect(stats.reset!.to_h).to eq(enqueued: 0, dropped: 0, sent: 0, failed: 0)
  end

  it "solleva su contatore sconosciuto" do
    expect { stats.increment(:nope) }.to raise_error(KeyError)
  end

  it "conta correttamente da thread concorrenti" do
    threads = Array.new(10) { Thread.new { 100.times { stats.increment(:sent) } } }
    threads.each(&:join)
    expect(stats[:sent]).to eq(1_000)
  end
end
