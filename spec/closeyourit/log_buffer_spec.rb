# frozen_string_literal: true

RSpec.describe CloseYourIt::LogBuffer do
  let(:client) { instance_double(CloseYourIt::Client, flush_logs: nil) }
  let(:configuration) do
    instance_double(CloseYourIt::Configuration, logs_batch_size: 3, logs_flush_interval: 0)
  end

  subject(:buffer) { described_class.new(client: client, configuration: configuration) }

  it "flusha quando raggiunge logs_batch_size" do
    buffer.add(:a)
    buffer.add(:b)
    expect(client).not_to have_received(:flush_logs)

    buffer.add(:c)
    expect(client).to have_received(:flush_logs).with(%i[a b c])
  end

  it "il flush manuale invia il buffer parziale e lo svuota" do
    buffer.add(:a)
    buffer.flush
    expect(client).to have_received(:flush_logs).with(%i[a])

    buffer.flush # ora vuoto → no-op
    expect(client).to have_received(:flush_logs).once
  end

  it "non flusha un buffer vuoto" do
    buffer.flush
    expect(client).not_to have_received(:flush_logs)
  end

  it "lo shutdown flusha il residuo" do
    buffer.add(:a)
    buffer.shutdown
    expect(client).to have_received(:flush_logs).with(%i[a])
  end

  describe "timer di flush periodico" do
    let(:configuration) do
      instance_double(CloseYourIt::Configuration, logs_batch_size: 100, logs_flush_interval: 7)
    end

    it "configura un TimerTask con execution_interval = logs_flush_interval" do
      buffer.add(:a)
      expect(buffer.timer).to be_a(Concurrent::TimerTask)
      expect(buffer.timer.execution_interval).to eq(7)
    ensure
      buffer.timer&.shutdown
    end
  end
end
