# Changelog

Tutte le modifiche degne di nota a questo progetto sono documentate qui.

Il formato si basa su [Keep a Changelog](https://keepachangelog.com/it/1.1.0/)
e il progetto aderisce al [Semantic Versioning](https://semver.org/lang/it/).

## [Unreleased]

### Aggiunto
- `CloseYourIt.stats`: contatori diagnostici thread-safe (`enqueued`, `dropped`, `sent`,
  `failed`) per rendere visibili i fallimenti silenziosi del trasporto fire-and-forget.
- Il trasporto ora logga a `warn` le risposte HTTP non-2xx (es. `401`, `404`, `500`),
  prima ignorate silenziosamente.
- Il background worker logga e conta gli eventi scartati quando la coda async è piena.
- `validate!` avvisa se `project_id` non ha forma UUID o se `endpoint_url` è privo di host.
- Scansione vulnerabilità delle dipendenze con `bundler-audit` nella CI.

### Modificato
- `.rubocop.yml`: `TargetRubyVersion` allineato a `4.0` (coerente con la gemspec).

## [0.2.0]

- Baseline: client di telemetria (eccezioni, query/metodi lenti, breadcrumbs, scope,
  sampling, scrubbing PII) con integrazione Rails/Sidekiq e trasporto fire-and-forget.
