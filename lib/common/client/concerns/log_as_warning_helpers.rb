# frozen_string_literal: true

module Common::Client
  module Concerns
    module LogAsWarningHelpers
      def warn_for_service_unavailable
        yield
      rescue Common::Exceptions::BackendServiceException => e
        Sentry.set_extras(log_as_warning: true) if e.original_status&.to_i == 503

        raise
      rescue Common::Client::Errors::HTTPError => e
        Sentry.set_extras(log_as_warning: true) if e.status&.to_i == 503

        raise
      end
    end
  end
end
