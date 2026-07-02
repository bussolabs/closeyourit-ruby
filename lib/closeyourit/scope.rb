# frozen_string_literal: true

require_relative "breadcrumb_buffer"
require_relative "performance/request_profile"

module CloseYourIt
  # Contesto per-richiesta (o per-job) isolato per execution-context (Fiber storage):
  # user/tags/extra/contexts/request. Letto da ErrorEvent#to_h sul thread chiamante (sincrono)
  # → il worker di invio non lo vede mai e lo scope non cola tra richieste.
  class Scope
    STORAGE_KEY = :__closeyourit_scope

    class << self
      # Scope dell'execution-context corrente. Usa `ActiveSupport::IsolatedExecutionState` quando
      # presente (rispetta isolation_level: thread su Puma, fiber su Falcon), altrimenti
      # `Thread.current` (thread-local puro, NON ereditato dai thread figli → niente bleed).
      def current
        store[STORAGE_KEY] ||= new
      end

      # Azzera lo scope corrente — chiamato in `ensure` da middleware e job (su Puma il
      # thread è riusato: senza reset lo scope colerebbe nella richiesta successiva).
      def reset!
        store[STORAGE_KEY] = nil
      end

      private

      def store
        if defined?(::ActiveSupport::IsolatedExecutionState)
          ::ActiveSupport::IsolatedExecutionState
        else
          ::Thread.current
        end
      end
    end

    attr_accessor :request, :trace_id, :rack_env
    attr_reader :user, :tags, :extra, :contexts, :breadcrumbs

    def initialize
      clear
    end

    def set_user(attributes)
      @user.merge!(stringify_keys(attributes))
    end

    def set_tag(key, value)
      @tags[key.to_s] = value
    end

    def set_tags(attributes)
      attributes.each { |key, value| set_tag(key, value) }
    end

    def set_context(key, attributes)
      @contexts[key.to_s] = stringify_keys(attributes)
    end

    def set_extra(key, value)
      @extra[key.to_s] = value
    end

    def add_breadcrumb(breadcrumb)
      @breadcrumbs.add(breadcrumb)
    end

    # Profilo di performance per-richiesta (query + HTTP esterne). Lazy: creato al primo accesso,
    # azzerato da #clear a fine richiesta. Il verdetto lo calcola Subscribers::RequestPerformance.
    def performance_profile
      @performance_profile ||= Performance::RequestProfile.new
    end

    def clear
      @user        = {}
      @tags        = {}
      @extra       = {}
      @contexts    = {}
      @request     = nil
      @rack_env    = nil
      @trace_id    = nil
      @breadcrumbs = BreadcrumbBuffer.new(CloseYourIt.configuration.max_breadcrumbs)
      @performance_profile = nil
    end

    # Sottoinsieme non vuoto in forma evento Sentry (user/tags/extra/contexts/request),
    # fuso nel payload da ErrorEvent#to_h. tags/extra/contexts passano dallo Scrubber (denylist
    # ricorsiva per chiave): il backend NON li ri-scruba (Errors::Ingest::Normalize li conserva
    # verbatim), quindi questa è l'unica rete di sicurezza contro le chiavi sensibili lì — R2.
    def to_event_hash
      {
        "user"        => serialize_user,
        "tags"        => scrub(presence(@tags)),
        "extra"       => scrub(presence(@extra)),
        "contexts"    => scrub(presence(@contexts)),
        "request"     => request_payload,
        "breadcrumbs" => breadcrumbs_payload
      }.reject { |_key, value| value.nil? }
    end

    private

    # Redige i valori delle chiavi sensibili preservando la struttura (es. contexts.runtime resta
    # intatto, solo i valori sotto chiavi sensibili diventano [FILTERED]). Riusa lo Scrubber della
    # configurazione, lo stesso percorso di breadcrumb.data e degli attributi di log.
    def scrub(hash)
      return hash if hash.nil?

      Scrubber.new(CloseYourIt.configuration).filter_params(hash)
    end

    # Request context + body params (`request.data`) estratti LAZY qui — cioè solo quando un
    # evento viene davvero costruito, mai sul percorso felice della richiesta.
    def request_payload
      return nil if @request.nil?

      data = request_body_data
      data ? @request.merge("data" => data) : @request
    end

    def request_body_data
      return nil unless CloseYourIt.configuration.capture_request_body
      return nil if @rack_env.nil?

      Rails::RequestBody.extract(@rack_env)
    rescue StandardError
      nil
    end

    # `user.id` sempre; email/ip_address/username solo con `send_pii` (il backend li strippa
    # comunque — difesa in profondità).
    def serialize_user
      return nil if @user.empty?
      return @user if CloseYourIt.configuration.send_pii

      presence(@user.slice("id"))
    end

    def breadcrumbs_payload
      return nil if @breadcrumbs.empty?

      { "values" => @breadcrumbs.to_a }
    end

    def presence(hash)
      hash.empty? ? nil : hash
    end

    def stringify_keys(attributes)
      attributes.each_with_object({}) { |(key, value), acc| acc[key.to_s] = value }
    end
  end
end
