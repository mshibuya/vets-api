# frozen_string_literal: true

module Crm
  class BaseRetriever
    attr_reader :user_mock_data, :entity_class

    def initialize(user_mock_data:, entity_class:)
      @user_mock_data = user_mock_data
      @entity_class = entity_class
    end

    def call
      data_array = fetch_data
      data_array.map { |item| entity_class.new(item) }
    rescue => e
      ::ErrorHandler.handle_service_error(e)
    end

    private

    def fetch_data
      data = if user_mock_data
               static = File.read('modules/ask_va_api/config/locales/static_data.json')
               JSON.parse(static, symbolize_names: true)
             else
               StaticData.new.call
             end
      filter_data(data)
    end

    def filter_data(data)
      raise NotImplementedError, 'Subclasses must implement the filter_data method'
    end
  end
end
