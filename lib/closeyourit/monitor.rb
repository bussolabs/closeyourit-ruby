# frozen_string_literal: true

require_relative "instrumenter"

module CloseYourIt
  # Macro per strumentare automaticamente un metodo:
  #
  #   class Report
  #     include CloseYourIt::Monitor
  #     def generate(...) = ...
  #     monitor :generate
  #   end
  #
  # Wrappa il metodo via `Module#prepend` cronometrandolo, senza cambiarne firma/risultato.
  module Monitor
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def monitor(method_name, label: nil)
        wrapper = Module.new do
          define_method(method_name) do |*args, **kwargs, &block|
            measured_label = label || "#{self.class}##{method_name}"
            CloseYourIt::Instrumenter.measure(measured_label, args: args, kwargs: kwargs) do
              super(*args, **kwargs, &block)
            end
          end
        end
        prepend(wrapper)
      end
    end
  end
end
