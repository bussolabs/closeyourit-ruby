# closeyourit-ruby

Client di telemetria per [CloseYourIt](../closeyourit-rails). Una gemma che il tuo progetto Rails
installa per inviare a CloseYourIt:

- **Eccezioni** → in **formato evento Sentry**, sul path Bearer `/api/v1/projects/:id/events`. Finiscono
  nel error-tracker (raggruppate, triage, promote-to-ticket) come quelle di un SDK Sentry.
- **Query/metodi lenti** → sul path `/api/v1/projects/:id/metrics` (pipeline metriche dedicata,
  raggruppate per signature con aggregati di durata) — ciò che Sentry/GlitchTip non danno bene.

È il **client primario** di CloseYourIt: replica e migliora ciò che fa un SDK Sentry (request context,
user/tag/contesto, breadcrumbs, errori nei background job, errori handled, sampling, messaggi) senza
dipendere dagli SDK Sentry.

Caratteristiche:
- **Contesto ricco** sull'errore: request HTTP (method/url/header), user/tag/contesto custom, breadcrumbs
  (cronologia query offuscate prima del crash).
- Cattura **automatica** di: eccezioni non gestite (Rack), errori in **ActiveJob/Sidekiq** (oggi persi),
  errori **handled** (`Rails.error.report`), query/metodi lenti.
- `capture_message`, **sampling** (`sample_rate`), ignore per **Regexp**, release detection automatica.
- Invio **fire-and-forget**: thread pool in background, non blocca la request, **non crasha mai** l'app.
- **No-op** se non configurata (sicura in sviluppo/test).
- **Privacy-by-default**: niente PII a meno di abilitarla esplicitamente.

> Design e contratto dati in [`PDR.md`](PDR.md).

## Installazione

Uso interno → install via git o path (no RubyGems):

```ruby
# Gemfile del progetto da monitorare
gem "closeyourit-ruby", git: "https://github.com/bussolabs/closeyourit-ruby"
# in sviluppo locale:
# gem "closeyourit-ruby", path: "../closeyourit-ruby"
```

## Ottenere credenziali

In CloseYourIt, area **Member → Project → tokens**, crea un token: ottieni il **Bearer secret**
(mostrato una volta) e l'**UUID del progetto**. Servono entrambi alla gemma.

## Configurazione

```ruby
# config/initializers/closeyourit.rb
CloseYourIt.init do |c|
  c.endpoint_url = ENV["CLOSEYOURIT_ENDPOINT_URL"]   # es. https://closeyour.it
  c.token        = ENV["CLOSEYOURIT_TOKEN"]          # Bearer secret del Projects::Token
  c.project_id   = ENV["CLOSEYOURIT_PROJECT_ID"]     # UUID del progetto su CloseYourIt
  c.environment  = Rails.env
end
```

**Senza `endpoint_url` / `token` / `project_id` la gemma è no-op** (nessun invio, nessun overhead). In
`production` un `endpoint_url` `http://` viene rifiutato (no-op + warning): il token viaggerebbe in chiaro.

### Opzioni

| Opzione | Default | Descrizione |
|---|---|---|
| `endpoint_url` | `ENV["CLOSEYOURIT_ENDPOINT_URL"]` | URL base (la gemma appende i path per-progetto) |
| `token` | `ENV["CLOSEYOURIT_TOKEN"]` | Bearer secret del progetto |
| `project_id` | `ENV["CLOSEYOURIT_PROJECT_ID"]` | UUID progetto (nel path di ingest) |
| `release` | `ENV["CLOSEYOURIT_RELEASE"]` | Versione riportata negli errori (opzionale) |
| `environment` | `Rails.env` / `RACK_ENV` / `"development"` | Ambiente riportato negli eventi |
| `excluded_exceptions` | `RoutingError`, `RecordNotFound` | Eccezioni da NON inviare — **String** (nome classe) o **Regexp** (match su nome/messaggio) |
| `before_send` | `nil` | `->(payload) { ... }` — scrub finale; ritorna payload o `nil` per scartare |
| `sample_rate` | `1.0` | Frazione di errori/messaggi inviata (`1.0` tutto, `0.0` niente) |
| `async_threads` | `cpu/2` | Thread di invio; `0` = sincrono (test) |
| `slow_query_threshold_ms` | `100` | Soglia query lente |
| `slow_method_threshold_ms` | `200` | Soglia metodi lenti |
| `capture_request` | `true` | Cattura il contesto HTTP della richiesta (method/url/header allowlist) |
| `request_header_allowlist` | `Accept`, `Content-Type`, `User-Agent`, `Referer` | Header inviati (mai Authorization/Cookie) |
| `breadcrumbs_enabled` | `true` | Cronologia (query offuscate + `add_breadcrumb`) allegata all'errore |
| `max_breadcrumbs` | `100` | Dimensione max del ring buffer breadcrumbs |
| `capture_handled_errors` | `true` | Cattura gli errori riportati via `Rails.error.report` |
| `report_active_job_errors` | `true` | Cattura gli errori dei job ActiveJob/Solid Queue/Sidekiq |
| `send_pii` | `false` | Master switch PII |
| `obfuscate_sql` | `true` | Maschera i literal nello SQL |
| `filter_parameters` | `[]` | Chiavi extra da redarre (mergiate con quelle di Rails) |
| `scrub_message_patterns` | `[]` | Regexp da redarre dai messaggi d'eccezione |

## Cosa cattura

### Eccezioni (automatico, con Rails) → error-tracker

Il Railtie inserisce un Rack middleware che cattura le eccezioni non gestite, le invia come **evento
Sentry** (`exception.values[]`, `level`, `event_id`, stacktrace) e le **ri-solleva** (l'app continua a
gestirle come prima). Cattura manuale ovunque:

```ruby
begin
  rischioso!
rescue => e
  CloseYourIt.capture_exception(e)
  raise
end
```

### Request context (automatico, con Rails)

Un Rack middleware allega a ogni evento il contesto HTTP della richiesta: **method**, **url** (senza
query string) e gli **header dell'allowlist** (`request_header_allowlist`, mai Authorization/Cookie).
Query string e IP solo con `send_pii`. Lo scope è resettato a fine richiesta (niente bleed tra request).

### Background job + errori handled (automatico, con Rails)

- **ActiveJob / Solid Queue / Sidekiq**: gli errori dei job (prima persi) vengono catturati con tag
  `job.class`/`job.queue` e contesto del job, poi ri-sollevati.
- **`Rails.error.report`** (ActiveSupport ErrorReporter): gli errori *handled* vengono inviati con
  `mechanism.handled = true` e il `level` mappato dalla severity. La dedup garantisce un solo invio anche
  se la stessa eccezione passa da più punti (Rack + job + reporter).

### Contesto, breadcrumbs e messaggi (manuale)

```ruby
CloseYourIt.set_user(id: account.id)              # solo id; email/ip solo se send_pii
CloseYourIt.set_tag(:tenant, current_tenant.slug)
CloseYourIt.set_context(:billing, { plan: "pro" })
CloseYourIt.set_extra(:cart_size, cart.size)
CloseYourIt.configure_scope { |s| s.set_tag(:area, "checkout") }

CloseYourIt.add_breadcrumb(message: "coupon applicato", category: "ui")  # cronologia pre-crash
CloseYourIt.capture_message("cache miss storm", level: "warning")        # messaggio diagnostico
```

Lo scope (user/tag/contesto/breadcrumbs) è **per-richiesta/job** e viene allegato automaticamente
all'evento d'errore catturato nello stesso contesto di esecuzione.

### Query lente (automatico, con Rails) → metriche

Il Railtie si iscrive a `sql.active_record`: ogni query oltre `slow_query_threshold_ms` (esclusi
`SCHEMA`/`CACHE`) viene inviata come `slow_query` alla pipeline metriche. Lo SQL è **offuscato** (bind esclusi).

### Metodi lenti → metriche

```ruby
# Blocco ad-hoc
CloseYourIt.measure("checkout.total") do
  calcolo_pesante
end

# Macro su un metodo (wrap automatico, firma e valore di ritorno invariati)
class Report
  include CloseYourIt::Monitor
  def generate(...) = ...
  monitor :generate
end
```

Viene inviato un `slow_method` solo se la durata supera `slow_method_threshold_ms`. **Gli argomenti
del metodo non vengono mai inviati** (solo label, durata, file:riga).

## Privacy & PII

Privacy-by-default (`send_pii = false`). In sintesi:

- **SQL**: inviato il template, **mai** i bind values; `obfuscate_sql` maschera anche i literal inline.
- **Chiavi sensibili** (`password`, `token`, `authorization`, `cookie`, `secret`, `api_key`, `csrf`,
  `credit_card`, `cvv`, `ssn`, `iban`, …) → `[FILTERED]`; estendibili con `filter_parameters`.
- **Messaggi d'eccezione**: inviati per il debug, ma redigibili con `scrub_message_patterns` /
  `before_send`.
- **Mai inviati**: variabili locali dei frame, argomenti dei metodi, IP/cookie/Authorization, token (che
  viaggia solo nell'header su HTTPS).

> Rischio residuo: `exception.value` e i nomi tabella/colonna nello SQL possono contenere dati di
> dominio. Usa `before_send`/`scrub_message_patterns` per azzerarli. Dettaglio in [`PDR.md` §9](PDR.md).

## Sviluppo

```bash
bundle install
bundle exec rspec        # test (WebMock, niente rete reale)
bundle exec rubocop      # lint (omakase)
COVERAGE_ENFORCE=1 bundle exec rspec   # gate coverage ≥90% line
```
