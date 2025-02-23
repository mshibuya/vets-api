# frozen_string_literal: true

module Map
  ##
  # A service client for handling HTTP requests to MAP API.
  #
  class Client
    extend Forwardable
    include SentryLogging

    attr_reader :settings

    def_delegators :settings, :service_name, :url

    ##
    # Builds a Client instance
    #
    # @param opts [Hash] options to create a Client
    #
    # @return [Map::Client] an instance of this class
    #
    def self.build
      new
    end

    def initialize
      @settings = Settings.check_in.map_api
    end

    ##
    # HTTP GET call to get the appointment data from MAP
    #
    # @return [Faraday::Response]
    #
    def appointments(token:, patient_icn:, query_params:)
      connection.post("/vaos/v1/patients/#{patient_icn}/appointments?#{query_params}") do |req|
        req.headers = default_headers.merge('X-VAMF-JWT' => token)
      end
    rescue => e
      Faraday::Response.new(body: e.original_body, status: e.original_status)
    end

    private

    ##
    # Create a Faraday connection object that glues the attributes
    # and the middleware stack for making our HTTP requests to the API
    #
    # @return [Faraday::Connection]
    #
    def connection
      Faraday.new(url:) do |conn|
        conn.use :breakers
        conn.response :raise_error, error_prefix: service_name
        conn.response :betamocks if mock_enabled?

        conn.adapter Faraday.default_adapter
      end
    end

    ##
    # Build a hash of default headers
    #
    # @return [Hash]
    #
    def default_headers
      {
        'Content-Type' => 'application/x-www-form-urlencoded'
      }
    end

    def mock_enabled?
      settings.mock || Flipper.enabled?('check_in_experience_mock_enabled') || false
    end
  end
end
