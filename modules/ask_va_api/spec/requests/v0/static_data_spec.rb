# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AskVAApi::V0::StaticDataController, type: :request do
  let(:logger) { instance_double(LogService) }
  let(:span) { instance_double(Datadog::Tracing::Span) }

  before do
    allow(LogService).to receive(:new).and_return(logger)
    allow(logger).to receive(:call).and_yield(span)
    allow(span).to receive(:set_tag)
    allow(Rails.logger).to receive(:error)
    allow_any_instance_of(Crm::CrmToken).to receive(:call).and_return('token')
  end

  shared_examples_for 'common error handling' do |status, action, error_message|
    it 'logs and renders error and sets datadog tags' do
      expect(response).to have_http_status(status)
      expect(JSON.parse(response.body)['error']).to eq(error_message)
      expect(logger).to have_received(:call).with(action)
      expect(span).to have_received(:set_tag).with('error', true)
      expect(span).to have_received(:set_tag).with('error.msg', error_message)
      expect(Rails.logger).to have_received(:error).with("Error during #{action}: #{error_message}")
    end
  end

  describe 'GET #index' do
    let(:index_path) { '/ask_va_api/v0/static_data' }
    let(:expected_response) { 'pong' }

    before do
      entity = OpenStruct.new(id: nil, info: 'pong')
      allow_any_instance_of(Crm::Service).to receive(:call).with(endpoint: 'topics').and_return(entity)
      get index_path
    end

    context 'when successful' do
      it 'returns status of 200 and the correct response data' do
        result = JSON.parse(response.body)['table']['info']
        expect(response).to have_http_status(:ok)
        expect(result).to eq(expected_response)
      end
    end
  end

  describe 'GET #categories' do
    let(:categories_path) { '/ask_va_api/v0/categories' }
    let(:expected_hash) do
      {
        'id' => '5a524deb-d864-eb11-bb24-000d3a579c45',
        'type' => 'categories',
        'attributes' => {
          'name' => 'VA Center for Minority Veterans',
          'allow_attachments' => false,
          'description' => nil,
          'display_name' => nil,
          'parent_id' => nil,
          'rank_order' => 18,
          'requires_authentication' => false
        }
      }
    end

    context 'when successful' do
      before do
        get categories_path, params: { user_mock_data: true }
      end

      it 'returns categories data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_hash))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'service error' }

      before do
        allow_any_instance_of(Crm::StaticData)
          .to receive(:call)
          .and_raise(StandardError)
        get categories_path
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: StandardError'
    end
  end

  describe 'GET #Topics' do
    let(:category) do
      AskVAApi::Categories::Entity.new({ id: '60524deb-d864-eb11-bb24-000d3a579c45' })
    end
    let(:expected_response) do
      {
        'id' => 'a52a8586-e764-eb11-bb23-000d3a579c3f',
        'type' => 'topics',
        'attributes' => {
          'name' => 'Supplemental Claim',
          'allow_attachments' => false,
          'description' => nil,
          'display_name' => nil,
          'parent_id' => '60524deb-d864-eb11-bb24-000d3a579c45',
          'rank_order' => 0,
          'requires_authentication' => false
        }
      }
    end
    let(:topics_path) { "/ask_va_api/v0/categories/#{category.id}/topics" }

    context 'when successful' do
      before { get topics_path, params: { user_mock_data: true } }

      it 'returns topics data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_response))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'service error' }

      before do
        allow_any_instance_of(Crm::StaticData)
          .to receive(:call)
          .and_raise(StandardError)
        get topics_path
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: StandardError'
    end
  end

  describe 'GET #SubTopics' do
    let(:topic) do
      AskVAApi::Topics::Entity.new({ id: 'f0ba9562-e864-eb11-bb23-000d3a579c44' })
    end
    let(:expected_response) do
      {
        'id' => '7d2dbcee-eb64-eb11-bb23-000d3a579b83',
        'type' => 'sub_topics',
        'attributes' => {
          'name' => 'Can I get a link on VA site to my site',
          'allow_attachments' => false,
          'description' => nil,
          'display_name' => nil,
          'parent_id' => 'f0ba9562-e864-eb11-bb23-000d3a579c44',
          'rank_order' => 0,
          'requires_authentication' => false
        }
      }
    end
    let(:subtopics_path) { "/ask_va_api/v0/topics/#{topic.id}/subtopics" }

    context 'when successful' do
      before { get subtopics_path, params: { user_mock_data: true } }

      it 'returns subtopics data' do
        expect(JSON.parse(response.body)['data']).to include(a_hash_including(expected_response))
        expect(response).to have_http_status(:ok)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'service error' }

      before do
        allow_any_instance_of(AskVAApi::SubTopics::Retriever)
          .to receive(:call)
          .and_raise(StandardError, 'standard error')
        get subtopics_path, params: { mock: true }
      end

      it_behaves_like 'common error handling', :internal_server_error, 'unexpected_error',
                      'standard error'
    end
  end

  describe 'GET #Zipcode' do
    let(:expected_response) do
      [{ 'id' => nil,
         'type' => 'zipcodes',
         'attributes' =>
          { 'zipcode' => '36010', 'city' => 'Autaugaville', 'state' => 'AL', 'lat' => 32.4312, 'lng' => -86.6549 } },
       { 'id' => nil,
         'type' => 'zipcodes',
         'attributes' => { 'zipcode' => '36011', 'city' => 'Millbrook', 'state' => 'AL', 'lat' => 32.5002,
                           'lng' => -86.3691 } },
       { 'id' => nil,
         'type' => 'zipcodes',
         'attributes' => { 'zipcode' => '36012', 'city' => 'Deatsville', 'state' => 'AL', 'lat' => 32.5997,
                           'lng' => -86.324 } }]
    end
    let(:zipcodes_path) { '/ask_va_api/v0/zipcodes' }

    context 'when successful' do
      before { get zipcodes_path, params: { zipcode: zip, mock: true } }

      context 'when zipcodes are found' do
        let(:zip) { '3601' }

        it 'returns zipcode data' do
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)['data'].first(3)).to eq(expected_response)
        end
      end

      context 'when no zipcode is found' do
        let(:zip) { '4000' }

        it 'returns an empty array' do
          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)['data']).to eq([])
        end
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'standard error' }

      before do
        allow_any_instance_of(AskVAApi::Zipcodes::Retriever)
          .to receive(:fetch_data)
          .and_raise(StandardError.new(error_message))
        get zipcodes_path, params: { mock: true }
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: standard error'
    end
  end

  describe 'GET #States' do
    let(:states_path) { '/ask_va_api/v0/states' }
    let(:scoped_response) do
      [
        { 'id' => nil, 'type' => 'states', 'attributes' => { 'name' => 'Alabama', 'code' => 'AL' } },
        { 'id' => nil, 'type' => 'states', 'attributes' => { 'name' => 'Alaska', 'code' => 'AK' } },
        { 'id' => nil, 'type' => 'states', 'attributes' => { 'name' => 'Arizona', 'code' => 'AZ' } }
      ]
    end

    context 'when successful' do
      before { get states_path, params: { mock: true } }

      it 'returns all the states' do
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['data'].first(3)).to eq(scoped_response)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'standard error' }

      before do
        allow_any_instance_of(AskVAApi::States::Retriever)
          .to receive(:fetch_data)
          .and_raise(StandardError.new(error_message))
        get states_path, params: { mock: true }
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: standard error'
    end
  end

  describe 'GET #Provinces' do
    let(:provinces_path) { '/ask_va_api/v0/provinces' }
    let(:scoped_response) do
      [
        { 'id' => nil, 'type' => 'provinces', 'attributes' => { 'name' => 'Alberta', 'abv' => 'AB' } },
        { 'id' => nil, 'type' => 'provinces', 'attributes' => { 'name' => 'British Columbia', 'abv' => 'BC' } },
        { 'id' => nil, 'type' => 'provinces', 'attributes' => { 'name' => 'Manitoba', 'abv' => 'MB' } }
      ]
    end

    context 'when successful' do
      before { get provinces_path, params: { mock: true } }

      it 'returns all the provinces' do
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)['data'].first(3)).to eq(scoped_response)
      end
    end

    context 'when an error occurs' do
      let(:error_message) { 'standard error' }

      before do
        allow_any_instance_of(AskVAApi::Provinces::Retriever)
          .to receive(:fetch_data)
          .and_raise(StandardError.new(error_message))
        get provinces_path, params: { mock: true }
      end

      it_behaves_like 'common error handling', :unprocessable_entity, 'service_error',
                      'StandardError: standard error'
    end
  end
end
