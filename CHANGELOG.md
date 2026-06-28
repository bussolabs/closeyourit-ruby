# Changelog

Tutte le modifiche degne di nota a questo progetto sono documentate qui.

Il formato si basa su [Keep a Changelog](https://keepachangelog.com/it/1.1.0/)
e il progetto aderisce al [Semantic Versioning](https://semver.org/lang/it/).

## [Unreleased]

## [0.3.2] - 2026-06-29

### Aggiunto
- **Log strutturati** verso l'ingest `/logs` di CloseYourIt:
  - `CloseYourIt.log(level, message, logger:, **attributes)` — costruisce e bufferizza una voce di log
    (livello normalizzato ai valori canonici del backend; `:warn` → `warning`).
  - `CloseYourIt.logger` — oggetto Logger-compatibile (`debug/info/warn/error/fatal`, `<<`, `add`) che
    inoltra a `CloseYourIt.log`. Usabile come logger esplicito dell'app, anche con attributes.
  - **Batching** in-memory thread-safe: flush a `logs_batch_size` (default 50), a `logs_flush_interval`
    (default 5s) o allo shutdown (`at_exit`); invio come array, fire-and-forget.
  - **Broadcast opt-in di `Rails.logger`** (`config.capture_rails_logs`, default OFF): re-inoltra i log
    dell'app ≥ `logs_min_level` (default `:info`). Richiede `BroadcastLogger` (Rails 7.1+).
  - Opzioni: `logs_enabled`, `logs_sample_rate`, `logs_batch_size`, `logs_flush_interval`,
    `capture_rails_logs`, `logs_min_level`. Gli `attributes` passano dallo `Scrubber` (denylist PII).
- **`trace_id`** per richiesta (`RequestContext`): riusa il request id di Rails/Rack se presente,
  altrimenti lo genera. Attaccato sia a `LogEvent` sia a `ErrorEvent` → correlazione log↔errori.

### Modificato
- Il logger diagnostico interno della gemma è ora `CloseYourIt.internal_logger` (prima `CloseYourIt.logger`);
  `CloseYourIt.logger` è riservato al logging applicativo strutturato.

## [0.3.1] - 2026-06-28

### Corretto
- `Transport`: segue fino a 2 redirect su POST preservando metodo + body (es. apex → www), così
  l'evento non si perde in silenzio quando l'host canonico risponde 301.

## [0.3.0] - 2026-06-28

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
