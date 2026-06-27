# frozen_string_literal: true

RSpec.describe CloseYourIt::BackgroundWorker do
  it "esegue il blocco in modalità sincrona quando threads == 0" do
    worker = described_class.new(threads: 0, max_queue: 30)
    ran = false

    worker.perform { ran = true }

    expect(ran).to be(true)
  end

  it "non solleva se il blocco fallisce (rescue + log)" do
    worker = described_class.new(threads: 0, max_queue: 30)
    allow(CloseYourIt.logger).to receive(:error)

    expect { worker.perform { raise "boom" } }.not_to raise_error
    expect(CloseYourIt.logger).to have_received(:error).with(/boom/)
  end

  it "configura la coda con fallback_policy :discard (threads > 0)" do
    worker = described_class.new(threads: 2, max_queue: 1)

    expect(worker.executor.fallback_policy).to eq(:discard)
  ensure
    worker&.shutdown
  end
end
