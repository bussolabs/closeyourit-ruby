# Changelog

Tutte le modifiche degne di nota a questo progetto sono documentate qui.

Il formato si basa su [Keep a Changelog](https://keepachangelog.com/it/1.1.0/)
e il progetto aderisce al [Semantic Versioning](https://semver.org/lang/it/).

## [Unreleased]

### Aggiunto
- **Context lines nei frame dello stacktrace**: ogni frame con file sorgente leggibile porta
  `pre_context`/`context_line`/`post_context` (config `context_lines`, default 3, `0` disattiva;
  `LineCache` bounded e thread-safe). L'error show del backend renderizza già lo snippet.
- **Body della richiesta nell'evento (`request.data`)**: estratto LAZY solo quando l'errore accade
  (mai sul percorso felice) — preferisce i params già parsati da Rails/Rack, fallback rilettura
  `rack.input` con rewind (JSON/form, cap 64 KB). Sanitizzato (upload → `[FILE: …]`, oggetti →
  `[OBJECT: …]`, stringhe troncate a 1024) e scrubbato (denylist + `filter_parameters`); il backend
  ri-scruba difensivamente. Config `capture_request_body` (default true).

## [0.3.4] - 2026-06-29

### Aggiunto
- **Rilevamento performance issue lato client** (opt-in `detect_performance_issues`, default OFF):
  `Performance::RequestProfile` accumula per-richiesta le query (per fingerprint + call-site, stile
  prosopite) e le chiamate HTTP esterne; `Performance::Rollup` emette verdetti `n_plus_one` /
  `high_query_count` / `slow_request` / `slow_external_http` come `PerformanceIssueEvent`
  (kind `performance_issue`, con `trace_id`) verso `/metrics`. `trace_id` aggiunto anche a
  `SlowQueryEvent`.

### Corretto
- **`capture_rails_logs` non agganciava il broadcast** (i log dell'app non arrivavano a CloseYourIt):
  l'initializer del railtie `closeyourit.capture_rails_logs` girava **prima** di
  `config/initializers/closeyourit.rb` (dove `CloseYourIt.init` imposta `capture_rails_logs = true`),
  quindi leggeva il default `false` e non agganciava mai il broadcast di `Rails.logger`. Aggiunto
  `after: :load_config_initializers` all'initializer.

## [0.3.3] - 2026-06-29

### Corretto
- **Scrubber — chiavi `pass*`**: la denylist ometteva `pass` bare (`pass_code`, `passkey`,
  `passphrase`) → allineata 1:1 al regex di backend/Dart (parità client-side, niente leak).
- **Scope — `tags`/`extra`/`contexts` scrubbati client-side** prima dell'invio: il backend non li
  ri-scrubbava sugli errori, quindi era l'unica difesa contro le chiavi sensibili in quei campi.
- **Log — chunking del batch a `LOGS_MAX_BATCH` (1000)**: un flush oltre il limite del server veniva
  rigettato in blocco (413) coi log persi; ora è spezzato in più POST sequenziali.

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
