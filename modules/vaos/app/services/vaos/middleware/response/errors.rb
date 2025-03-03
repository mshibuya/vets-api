# frozen_string_literal: true

module VAOS
  module Middleware
    module Response
      class Errors < Faraday::Response::Middleware
        def on_complete(env)
          return if env.success?

          Sentry.set_extras(vamf_status: env.status, vamf_body: env.response_body, vamf_url: env.url)
          raise VAOS::Exceptions::BackendServiceException, env
        end
      end
    end
  end
end

Faraday::Response.register_middleware vaos_errors: VAOS::Middleware::Response::Errors
