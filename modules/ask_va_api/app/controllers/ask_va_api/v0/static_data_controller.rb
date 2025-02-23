# frozen_string_literal: true

module AskVAApi
  module V0
    class StaticDataController < ApplicationController
      skip_before_action :authenticate
      around_action :handle_exceptions, except: %i[index]

      def index
        service = Crm::Service.new(icn: 'a')
        data = service.call(endpoint: 'topics')
        render json: data.to_json, status: :ok
      end

      def categories
        get_resource('categories', user_mock_data: params[:user_mock_data])
        render_result(@categories)
      end

      def provinces
        get_resource('provinces', service: mock_service)
        render_result(@provinces)
      end

      def states
        get_resource('states', service: mock_service)
        render_result(@states)
      end

      def subtopics
        get_resource('sub_topics', topic_id: params[:topic_id], user_mock_data: params[:user_mock_data])
        render_result(@sub_topics)
      end

      def topics
        get_resource('topics', category_id: params[:category_id], user_mock_data: params[:user_mock_data])
        render_result(@topics)
      end

      def zipcodes
        get_resource('zipcodes', zip: params[:zipcode], service: mock_service)
        render_result(@zipcodes)
      end

      private

      def get_resource(resource_type, options = {})
        camelize_resource = resource_type.camelize
        retriever_class = constantize_class("AskVAApi::#{camelize_resource}::Retriever")
        serializer_class = constantize_class("AskVAApi::#{camelize_resource}::Serializer")
        entity_class = constantize_class("AskVAApi::#{camelize_resource}::Entity")

        options.merge!(entity_class:) unless %w[provinces states zipcodes].include?(resource_type)

        data = retriever_class.new(**options).call

        serialized_data = serializer_class.new(data).serializable_hash

        instance_variable_set("@#{resource_type}", Result.new(payload: serialized_data, status: :ok))
      end

      def constantize_class(class_name)
        class_name.constantize
      end

      def mock_service
        DynamicsMockService.new(icn: nil, logger: nil) if params[:mock]
      end

      def render_result(resource)
        render json: resource.payload, status: resource.status
      end
      Result = Struct.new(:payload, :status, keyword_init: true)
    end
  end
end
