# frozen_string_literal: true

require_relative "lib/closeyourit/version"

Gem::Specification.new do |spec|
  spec.name        = "closeyourit-ruby"
  spec.version     = CloseYourIt::VERSION
  spec.authors     = [ "Alessio Bussolari" ]
  spec.email       = [ "hello@bussolarialessio.me" ]

  spec.summary     = "Client di telemetria per CloseYourIt (errori + query/metodi lenti)."
  spec.description = "Gemma client che cattura eccezioni e le statistiche di query e metodi lenti " \
                     "e le invia, fire-and-forget, all'endpoint di ingest di CloseYourIt."
  spec.homepage    = "https://github.com/bussolabs/closeyourit-ruby"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files        = Dir["lib/**/*.rb", "README.md", "LICENSE.txt"]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "concurrent-ruby", "~> 1.3"
end
