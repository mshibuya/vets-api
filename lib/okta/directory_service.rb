# frozen_string_literal: true

require 'rest-client'

module Okta
  class DirectoryService < Common::Client::Base
    def scopes(category)
      # if the category is health we need to call a specific server instead of relying on querying by name,
      # since there is a 'health/systems' auth server that would affect results

      base_url = Settings.authorization_server_scopes_api.auth_server.url

      category = category.downcase

      scopes_url = "#{base_url}/#{category}/scopes"

      headers = { apiKey: Settings.connected_apps_api.connected_apps.api_key }

      response = RestClient::Request.execute(method: :get, url: scopes_url, headers:)

      if response.code == 200
        begin
          JSON.parse(response.body)

        # response has 200 status but content of response body is not valid json
        rescue JSON::ParserError
          { 'error' => 'Failed to parse JSON response' }
        end
      else
        # category is found but no scopes are returned (204)
        []
      end
    end
  end
end
