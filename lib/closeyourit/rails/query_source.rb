# frozen_string_literal: true

module CloseYourIt
  module Rails
    # Call-site applicativo di una query lenta (privacy-safe → sempre inviato): primo frame della
    # backtrace ripulito da Rails.backtrace_cleaner (rimuove gem/framework, tiene il codice app),
    # senza il suffisso ":in '...'". Es. "app/models/order.rb:42".
    module QuerySource
      def self.from_caller(backtrace = caller)
        frame = ::Rails.backtrace_cleaner.clean(backtrace).first
        return nil if frame.nil?

        frame.split(":in ", 2).first
      end
    end
  end
end
