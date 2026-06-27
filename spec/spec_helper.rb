# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  enable_coverage :branch
  add_filter "/spec/"
  # Gate ≥90% line attivato a fine sviluppo (vedi PDR §12 gate finale):
  # minimum_coverage line: 90 quando ENV["COVERAGE_ENFORCE"].
  minimum_coverage line: 90 if ENV["COVERAGE_ENFORCE"]
end

require "closeyourit-ruby"
require "webmock/rspec"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Ogni test parte da configurazione e client puliti.
  config.before do
    CloseYourIt.instance_variable_set(:@configuration, nil)
    CloseYourIt.instance_variable_set(:@client, nil)
  end
end
