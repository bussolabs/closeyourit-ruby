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

  it "ritorna true quando il blocco viene accettato (sincrono)" do
    worker = described_class.new(threads: 0, max_queue: 30)

    expect(worker.perform { :ok }).to be(true)
  end

  it "scarta, logga a warn e incrementa stats.dropped a coda piena" do
    worker = described_class.new(threads: 1, max_queue: 1)
    allow(CloseYourIt.logger).to receive(:warn)
    gate = Queue.new

    worker.perform { gate.pop } # occupa l'unico thread finché non sblocchiamo
    worker.perform { :queued }  # riempie l'unico slot di coda

    expect { @rejected = worker.perform { :overflow } }
      .to change { CloseYourIt.stats[:dropped] }.by(1)
    expect(@rejected).to be(false)
    expect(CloseYourIt.logger).to have_received(:warn).with(/coda piena/)
  ensure
    gate << :go
    worker&.shutdown
  end
end
