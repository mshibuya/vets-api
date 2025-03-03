# frozen_string_literal: true

require 'rails_helper'
require 'support/rx_client_helpers'
require 'support/shared_examples_for_mhv'

# rubocop:disable Layout/LineLength
RSpec.describe 'prescriptions', type: :request do
  include Rx::ClientHelpers
  include SchemaMatchers

  let(:va_patient) { true }
  let(:current_user) do
    build(:user, :mhv, authn_context: LOA::IDME_LOA3_VETS,
                       va_patient:,
                       mhv_account_type:,
                       sign_in: { service_name: SignIn::Constants::Auth::IDME })
  end
  let(:inflection_header) { { 'X-Key-Inflection' => 'camel' } }

  before do
    allow(Rx::Client).to receive(:new).and_return(authenticated_client)
    sign_in_as(current_user)
  end

  context 'Basic User' do
    let(:mhv_account_type) { 'Basic' }

    before { get '/my_health/v1/prescriptions/13651310' }

    include_examples 'for user account level', message: 'You do not have access to prescriptions'
    include_examples 'for non va patient user', authorized: false, message: 'You do not have access to prescriptions'
  end

  %w[Premium Advanced].each do |account_level|
    context "#{account_level} User" do
      let(:mhv_account_type) { account_level }

      context 'not a va patient' do
        before { get '/my_health/v1/prescriptions/13651310' }

        let(:va_patient) { false }
        let(:current_user) do
          build(:user,
                :mhv,
                :no_vha_facilities,
                authn_context: LOA::IDME_LOA3_VETS,
                va_patient:,
                mhv_account_type:,
                sign_in: { service_name: SignIn::Constants::Auth::IDME })
        end

        include_examples 'for non va patient user', authorized: false, message: 'You do not have access to prescriptions'
      end

      it 'responds to GET #show' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_single_prescription_v1') do
          get '/my_health/v1/prescriptions/12284508'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_single')
      end

      it 'responds to GET #show with camel-inlfection' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_single_prescription_v1') do
          get '/my_health/v1/prescriptions/12284508', headers: inflection_header
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescription_single')
      end

      it 'responds to GET #index with no parameters' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_v1') do
          get '/my_health/v1/prescriptions'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('prescription_name' => 'ASC')
      end

      it 'responds to GET #index with no parameters when camel-inflected' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_v1') do
          get '/my_health/v1/prescriptions', headers: inflection_header
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('prescriptionName' => 'ASC')
      end

      it 'responds to GET #index with images' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_with_images_v1') do
          get '/my_health/v1/prescriptions?&sort[]=prescription_name&sort[]=dispensed_date&include_image=true'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
        item_index = JSON.parse(response.body)['data'].find_index { |item| item['attributes']['prescription_image'] }
        expect(item_index).not_to be_nil
      end

      it 'responds to GET #get_prescription_image with image' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_prescription_image_v1') do
          get '/my_health/v1/prescriptions?/prescriptions/get_prescription_image/00013264681'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
        expect(JSON.parse(response.body)['data']).to be_truthy
      end

      it 'responds to GET #index with pagination parameters' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_paginated_list_of_prescriptions') do
          get '/my_health/v1/prescriptions?page=1&per_page=10'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
        expect(JSON.parse(response.body)['meta']['pagination']['current_page']).to eq(1)
        expect(JSON.parse(response.body)['meta']['pagination']['per_page']).to eq(10)
      end

      it 'responds to GET #index with pagination parameters when camel-inflected' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_paginated_list_of_prescriptions') do
          get '/my_health/v1/prescriptions?page=2&per_page=20', headers: inflection_header
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
        expect(JSON.parse(response.body)['meta']['pagination']['currentPage']).to eq(2)
        expect(JSON.parse(response.body)['meta']['pagination']['perPage']).to eq(20)
      end

      it 'responds to GET #index with prescription name as sort parameter' do
        VCR.use_cassette('rx_client/prescriptions/gets_sorted_list_by_prescription_name') do
          get '/my_health/v1/prescriptions?page=7&per_page=20&sort[]=prescription_name&sort[]=dispensed_date'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list_paginated')
        response_data = JSON.parse(response.body)['data']
        item_index = response_data.find_index { |item| item['orderable_item'] == 'GABAPENTIN' }

        # Make sure 'Gabapentin' does not exist on final page and is being alphabetized correctly
        expect(item_index).to be_nil
      end

      it 'responds to GET #index with refill_status=active' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_active_prescriptions') do
          get '/my_health/v1/prescriptions?refill_status=active'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescriptions_list')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('prescription_name' => 'ASC')
      end

      it 'responds to GET #index with refill_status=active when camel-inflected' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_active_prescriptions_v1') do
          get '/my_health/v1/prescriptions?refill_status=active', headers: inflection_header
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list')
        expect(JSON.parse(response.body)['meta']['sort']).to eq('prescriptionName' => 'ASC')
      end

      it 'responds to GET #index with filter' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_filtered_v1') do
          get '/my_health/v1/prescriptions?filter[[refill_status][eq]]=refillinprocess'
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_response_schema('my_health/prescriptions/v1/prescription_list_filtered')
      end

      it 'responds to GET #index with filter when camel-inflected' do
        VCR.use_cassette('rx_client/prescriptions/gets_a_list_of_all_prescriptions_filtered_v1') do
          get '/my_health/v1/prescriptions?filter[[refill_status][eq]]=refillinprocess', headers: inflection_header
        end

        expect(response).to be_successful
        expect(response.body).to be_a(String)
        expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescription_list_filtered')
      end

      it 'responds to POST #refill' do
        VCR.use_cassette('rx_client/prescriptions/refills_a_prescription') do
          patch '/my_health/v1/prescriptions/13650545/refill'
        end

        expect(response).to be_successful
        expect(response.body).to be_empty
      end

      context 'nested resources' do
        it 'responds to GET #show of nested tracking resource' do
          VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_a_list_of_tracking_history_for_a_prescription') do
            get '/my_health/v1/prescriptions/13650541/trackings'
          end

          expect(response).to be_successful
          expect(response.body).to be_a(String)
          expect(response).to match_response_schema('trackings')
          expect(JSON.parse(response.body)['meta']['sort']).to eq('shipped_date' => 'DESC')
        end

        it 'responds to GET #index with sorted_dispensed_date' do
          VCR.use_cassette('rx_client/prescriptions/gets_a_sorted_by_custom_field_list_of_all_prescriptions_v1') do
            get '/my_health/v1/prescriptions?sort[]=-dispensed_date&sort[]=prescription_name', headers: inflection_header
          end

          res = JSON.parse(response.body)

          dates = res['data'].map { |d| DateTime.parse(d['attributes']['sortedDispensedDate']) }
          is_sorted = dates.each_cons(2).all? { |item1, item2| item1 >= item2 }
          expect(response).to be_successful
          expect(response.body).to be_a(String)
          expect(is_sorted).to be_truthy
          expect(response).to match_camelized_response_schema('my_health/prescriptions/v1/prescriptions_list')

          metadata = { 'prescriptionName' => 'ASC', 'dispensedDate' => 'DESC' }
          expect(JSON.parse(response.body)['meta']['sort']).to eq(metadata)
        end

        it 'responds to GET #show of nested tracking resource when camel-inflected' do
          VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_a_list_of_tracking_history_for_a_prescription') do
            get '/my_health/v1/prescriptions/13650541/trackings', headers: inflection_header
          end

          expect(response).to be_successful
          expect(response.body).to be_a(String)
          expect(response).to match_camelized_response_schema('trackings')
          expect(JSON.parse(response.body)['meta']['sort']).to eq('shippedDate' => 'DESC')
        end

        it 'responds to GET #show of nested tracking resource with a shipment having no other prescriptions' do
          VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_tracking_with_empty_other_prescriptions') do
            get '/my_health/v1/prescriptions/13650541/trackings'
          end

          expect(response).to be_successful
          expect(response.body).to be_a(String)
          expect(response).to match_response_schema('trackings')
          expect(JSON.parse(response.body)['meta']['sort']).to eq('shipped_date' => 'DESC')
        end

        it 'responds to GET #show of nested tracking resource with a shipment having no other prescriptions when camel-inflected' do
          VCR.use_cassette('rx_client/prescriptions/nested_resources/gets_tracking_with_empty_other_prescriptions') do
            get '/my_health/v1/prescriptions/13650541/trackings', headers: inflection_header
          end

          expect(response).to be_successful
          expect(response.body).to be_a(String)
          expect(response).to match_camelized_response_schema('trackings')
          expect(JSON.parse(response.body)['meta']['sort']).to eq('shippedDate' => 'DESC')
        end
      end

      context 'preferences' do
        it 'responds to GET #show of preferences' do
          VCR.use_cassette('rx_client/preferences/gets_rx_preferences') do
            get '/my_health/v1/prescriptions/preferences'
          end

          expect(response).to be_successful
          expect(response.body).to be_a(String)
          attrs = JSON.parse(response.body)['data']['attributes']
          expect(attrs['email_address']).to eq('Praneeth.Gaganapally@va.gov')
          expect(attrs['rx_flag']).to be true
        end

        it 'responds to PUT #update of preferences' do
          VCR.use_cassette('rx_client/preferences/sets_rx_preferences', record: :none) do
            params = { email_address: 'kamyar.karshenas@va.gov',
                       rx_flag: false }
            put '/my_health/v1/prescriptions/preferences', params:
          end

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)['data']['id'])
            .to eq('59623c5f11b874409315b05a254a7ace5f6a1b12a21334f7b3ceebe1f1854948')
          expect(JSON.parse(response.body)['data']['attributes'])
            .to eq('email_address' => 'kamyar.karshenas@va.gov', 'rx_flag' => false)
        end

        it 'requires all parameters for update' do
          VCR.use_cassette('rx_client/preferences/sets_rx_preferences', record: :none) do
            params = { email_address: 'kamyar.karshenas@va.gov' }
            put '/my_health/v1/prescriptions/preferences', params:
          end

          expect(response).to have_http_status(:unprocessable_entity)
        end

        it 'returns a custom exception mapped from i18n when email contains spaces' do
          VCR.use_cassette('rx_client/preferences/raises_a_backend_service_exception_when_email_includes_spaces') do
            params = { email_address: 'kamyar karshenas@va.gov',
                       rx_flag: false }
            put '/my_health/v1/prescriptions/preferences', params:
          end

          expect(response).to have_http_status(:unprocessable_entity)
          expect(JSON.parse(response.body)['errors'].first['code']).to eq('RX157')
        end
      end
    end
  end
end
# rubocop:enable Layout/LineLength
