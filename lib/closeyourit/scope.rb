# frozen_string_literal: true

require_relative "breadcrumb_buffer"

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

    attr_accessor :request
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

    def clear
      @user        = {}
      @tags        = {}
      @extra       = {}
      @contexts    = {}
      @request     = nil
      @breadcrumbs = BreadcrumbBuffer.new(CloseYourIt.configuration.max_breadcrumbs)
    end

    # Sottoinsieme non vuoto in forma evento Sentry (user/tags/extra/contexts/request),
    # fuso nel payload da ErrorEvent#to_h.
    def to_event_hash
      {
        "user"        => serialize_user,
        "tags"        => presence(@tags),
        "extra"       => presence(@extra),
        "contexts"    => presence(@contexts),
        "request"     => @request,
        "breadcrumbs" => breadcrumbs_payload
      }.reject { |_key, value| value.nil? }
    end

    private

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
