# frozen_string_literal: true

require 'rails_helper'
require_relative '../support/helpers/sis_session_helper'
require_relative '../support/matchers/json_schema_matcher'

RSpec.describe 'user', type: :request do
  include JsonSchemaMatchers

  let(:attributes) { response.parsed_body.dig('data', 'attributes') }

  describe 'GET /mobile/v0/user' do
    let!(:user) do
      sis_user(
        first_name: 'GREG',
        middle_name: 'A',
        last_name: 'ANDERSON',
        email: 'va.api.user+idme.008@gmail.com',
        birth_date: '1970-08-12',
        idme_uuid: 'b2fab2b5-6af0-45e1-a9e2-394347af91ef',
        cerner_facility_ids: %w[757 358 999],
        vha_facility_ids: %w[757 358 999]
      )
    end

    before(:all) do
      Flipper.disable(:mobile_lighthouse_letters)
    end

    context 'with no upstream errors' do
      before do
        VCR.use_cassette('mobile/payment_information/payment_information') do
          VCR.use_cassette('mobile/user/get_facilities') do
            VCR.use_cassette('mobile/va_profile/demographics/demographics') do
              get '/mobile/v0/user', headers: sis_headers
            end
          end
        end
      end

      it 'returns an ok response' do
        expect(response).to have_http_status(:ok)
      end

      it 'returns a user profile response with the expected schema' do
        expect(response.body).to match_json_schema('user')
      end

      it 'includes the users names' do
        expect(attributes['profile']).to include(
          'firstName' => 'GREG',
          'middleName' => 'A',
          'lastName' => 'ANDERSON'
        )
      end

      it 'includes the users sign-in email' do
        expect(attributes['profile']).to include(
          'signinEmail' => 'va.api.user+idme.008@gmail.com'
        )
      end

      it 'includes the users contact email id' do
        expect(attributes.dig('profile', 'contactEmail', 'id')).to eq(456)
      end

      it 'includes the users contact email addrss' do
        expect(attributes.dig('profile', 'contactEmail', 'emailAddress')).to match(/person\d+@example.com/)
      end

      it 'includes the users birth date' do
        expect(attributes['profile']).to include(
          'birthDate' => '1970-08-12'
        )
      end

      it 'includes the expected residential address' do
        expect(attributes['profile']).to include(
          'residentialAddress' => {
            'id' => 123,
            'addressLine1' => '140 Rock Creek Rd',
            'addressLine2' => nil,
            'addressLine3' => nil,
            'addressPou' => 'RESIDENCE/CHOICE',
            'addressType' => 'DOMESTIC',
            'city' => 'Washington',
            'countryCodeIso3' => 'USA',
            'internationalPostalCode' => nil,
            'province' => nil,
            'stateCode' => 'DC',
            'zipCode' => '20011',
            'zipCodeSuffix' => nil
          }
        )
      end

      it 'includes the expected mailing address' do
        expect(attributes['profile']).to include(
          'mailingAddress' => {
            'id' => 124,
            'addressLine1' => '140 Rock Creek Rd',
            'addressLine2' => nil,
            'addressLine3' => nil,
            'addressPou' => 'CORRESPONDENCE',
            'addressType' => 'DOMESTIC',
            'city' => 'Washington',
            'countryCodeIso3' => 'USA',
            'internationalPostalCode' => nil,
            'province' => nil,
            'stateCode' => 'DC',
            'zipCode' => '20011',
            'zipCodeSuffix' => nil
          }
        )
      end

      it 'includes a home phone number' do
        expect(attributes['profile']['homePhoneNumber']).to include(
          {
            'id' => 789,
            'areaCode' => '303',
            'countryCode' => '1',
            'extension' => nil,
            'phoneNumber' => '5551234',
            'phoneType' => 'HOME'
          }
        )
      end

      it 'includes a mobile phone number' do
        expect(attributes['profile']['mobilePhoneNumber']).to include(
          {
            'id' => 790,
            'areaCode' => '303',
            'countryCode' => '1',
            'extension' => nil,
            'phoneNumber' => '5551234',
            'phoneType' => 'MOBILE'
          }
        )
      end

      it 'includes a work phone number' do
        expect(attributes['profile']['workPhoneNumber']).to include(
          {
            'id' => 791,
            'areaCode' => '303',
            'countryCode' => '1',
            'extension' => nil,
            'phoneNumber' => '5551234',
            'phoneType' => 'WORK'
          }
        )
      end

      it 'includes sign-in service' do
        expect(attributes['profile']['signinService']).to eq('idme')
      end

      it 'includes the service the user has access to' do
        expect(attributes['authorizedServices']).to eq(
          %w[
            appeals
            appointments
            claims
            decisionLetters
            directDepositBenefits
            directDepositBenefitsUpdate
            disabilityRating
            genderIdentity
            lettersAndDocuments
            militaryServiceHistory
            paymentHistory
            preferredName
            scheduleAppointments
            userProfileUpdate
          ]
        )
      end

      it 'includes a complete list of mobile api services (even if the user does not have access to them)' do
        expect(JSON.parse(response.body).dig('meta', 'availableServices')).to eq(
          %w[
            appeals
            appointments
            claims
            decisionLetters
            directDepositBenefits
            directDepositBenefitsUpdate
            disabilityRating
            genderIdentity
            lettersAndDocuments
            militaryServiceHistory
            paymentHistory
            preferredName
            prescriptions
            scheduleAppointments
            secureMessaging
            userProfileUpdate
          ]
        )
      end

      it 'includes a health attribute with user facilities and is_cerner_patient' do
        expect(attributes['health']).to include(
          {
            'isCernerPatient' => true,
            'facilities' => [
              {
                'facilityId' => '757',
                'isCerner' => true,
                'facilityName' => 'Cheyenne VA Medical Center'
              },
              {
                'facilityId' => '358',
                'isCerner' => true,
                'facilityName' => 'COLUMBUS VAMC'
              }
            ]
          }
        )
      end

      context 'when user object birth_date is nil' do
        let!(:user) { sis_user(birth_date: nil) }

        before do
          VCR.use_cassette('mobile/payment_information/payment_information') do
            VCR.use_cassette('mobile/user/get_facilities_no_ids', match_requests_on: %i[method uri]) do
              VCR.use_cassette('mobile/va_profile/demographics/demographics') do
                get '/mobile/v0/user', headers: sis_headers
              end
            end
          end
        end

        it 'returns a nil birthdate' do
          expect(response).to have_http_status(:ok)
          expect(attributes['profile']).to include(
            'birthDate' => nil
          )
        end
      end
    end

    context 'when the upstream va profile service returns a 502' do
      before do
        allow_any_instance_of(VAProfile::ContactInformation::Service).to receive(:get_person).and_raise(
          Common::Exceptions::BackendServiceException.new('VET360_502')
        )
      end

      it 'returns a service unavailable error' do
        VCR.use_cassette('mobile/user/get_facilities', match_requests_on: %i[method uri]) do
          get '/mobile/v0/user', headers: sis_headers
        end

        expect(response).to have_http_status(:bad_gateway)
        expect(response.body).to match_json_schema('errors')
      end
    end

    context 'when the upstream va profile service returns a 404' do
      before do
        allow_any_instance_of(VAProfile::ContactInformation::Service).to receive(:get_person).and_raise(
          Common::Exceptions::RecordNotFound.new(user.uuid)
        )
      end

      it 'returns a record not found error' do
        VCR.use_cassette('mobile/va_profile/demographics/demographics') do
          VCR.use_cassette('mobile/user/get_facilities', match_requests_on: %i[method uri]) do
            get '/mobile/v0/user', headers: sis_headers
          end
        end

        expect(response).to have_http_status(:not_found)
        expect(response.body).to match_json_schema('errors')
        expect(response.parsed_body).to eq(
          {
            'errors' => [
              {
                'title' => 'Record not found',
                'detail' => "The record identified by #{user.uuid} could not be found",
                'code' => '404',
                'status' => '404'
              }
            ]
          }
        )
      end
    end

    context 'when the va profile service throws an argument error' do
      before do
        allow_any_instance_of(VAProfile::ContactInformation::Service).to receive(:get_person).and_raise(
          ArgumentError.new
        )
      end

      it 'returns a bad gateway error' do
        get '/mobile/v0/user', headers: sis_headers

        expect(response).to have_http_status(:internal_server_error)
        expect(response.body).to match_json_schema('errors')
      end
    end

    context 'when the va profile service throws an client error' do
      before do
        allow_any_instance_of(VAProfile::ContactInformation::Service).to receive(:get_person).and_raise(
          Common::Client::Errors::ClientError.new
        )
      end

      it 'returns a bad gateway error' do
        VCR.use_cassette('mobile/user/get_facilities', match_requests_on: %i[method uri]) do
          get '/mobile/v0/user', headers: sis_headers
        end

        expect(response).to have_http_status(:service_unavailable)
        expect(response.body).to match_json_schema('errors')
      end
    end

    context 'empty get_facility test' do
      before do
        VCR.use_cassette('mobile/payment_information/payment_information') do
          VCR.use_cassette('mobile/user/get_facilities_empty', match_requests_on: %i[method uri]) do
            VCR.use_cassette('mobile/va_profile/demographics/demographics') do
              get '/mobile/v0/user', headers: sis_headers
            end
          end
        end
      end

      it 'returns empty appropriate facilities list' do
        expect(attributes['health']).to include(
          {
            'isCernerPatient' => true,
            'facilities' => [
              {
                'facilityId' => '757',
                'isCerner' => true,
                'facilityName' => ''
              },
              {
                'facilityId' => '358',
                'isCerner' => true,
                'facilityName' => ''
              }
            ]
          }
        )
      end
    end

    describe 'fax number' do
      let(:user_request) do
        VCR.use_cassette('mobile/payment_information/payment_information') do
          VCR.use_cassette('mobile/user/get_facilities', match_requests_on: %i[method uri]) do
            VCR.use_cassette('mobile/va_profile/demographics/demographics') do
              get '/mobile/v0/user', headers: sis_headers
            end
          end
        end
      end

      context 'when the user have a fax number' do
        it 'returns expected fax number' do
          user_request
          expect(attributes['profile']['faxNumber']).to eq(
            {
              'id' => 792,
              'areaCode' => '303',
              'countryCode' => '1',
              'extension' => nil,
              'phoneNumber' => '5551234',
              'phoneType' => 'FAX'
            }
          )
        end
      end

      # Another team will remove this method from the user model
      context 'when user model does not have a fax number method' do
        before do
          allow_any_instance_of(VAProfileRedis::ContactInformation).to receive(:try).with(:fax_number).and_return(nil)
        end

        it 'sets fax number to nil' do
          user_request
          expect(response).to have_http_status(:ok)
          expect(attributes['profile']['faxNumber']).to eq(nil)
        end
      end
    end

    describe 'vet360 linking' do
      context 'when user has a vet360_id' do
        it 'does not enqueue vet360 linking job' do
          expect(Mobile::V0::Vet360LinkingJob).not_to receive(:perform_async)

          VCR.use_cassette('mobile/payment_information/payment_information') do
            VCR.use_cassette('mobile/user/get_facilities') do
              VCR.use_cassette('mobile/va_profile/demographics/demographics') do
                get '/mobile/v0/user', headers: sis_headers
              end
            end
          end
          expect(response).to have_http_status(:ok)
        end

        it 'flips mobile user vet360_linked to true if record exists' do
          Mobile::User.create(icn: user.icn, vet360_link_attempts: 1, vet360_linked: false)

          VCR.use_cassette('mobile/payment_information/payment_information') do
            VCR.use_cassette('mobile/user/get_facilities') do
              VCR.use_cassette('mobile/va_profile/demographics/demographics') do
                get '/mobile/v0/user', headers: sis_headers

                expect(Mobile::User.where(icn: user.icn, vet360_link_attempts: 1, vet360_linked: true)).to exist
              end
            end
          end
          expect(response).to have_http_status(:ok)
        end
      end

      context 'when user does not have a vet360_id' do
        let!(:user) { sis_user(vet360_id: nil) }

        it 'enqueues vet360 linking job' do
          expect(Mobile::V0::Vet360LinkingJob).to receive(:perform_async)

          VCR.use_cassette('mobile/payment_information/payment_information') do
            VCR.use_cassette('mobile/user/get_facilities_no_ids') do
              VCR.use_cassette('mobile/va_profile/demographics/demographics') do
                get '/mobile/v0/user', headers: sis_headers
              end
            end
          end
          expect(response).to have_http_status(:ok)
        end
      end
    end
  end

  describe 'POST /mobile/v0/user/logged-in' do
    let!(:user) { sis_user }

    it 'returns an ok response' do
      post '/mobile/v0/user/logged-in', headers: sis_headers
      expect(response).to have_http_status(:ok)
    end

    describe 'vet360 linking' do
      context 'when user has a vet360_id' do
        it 'does not enqueue vet360 linking job' do
          expect(Mobile::V0::Vet360LinkingJob).not_to receive(:perform_async)

          post '/mobile/v0/user/logged-in', headers: sis_headers
        end

        it 'flips mobile user vet360_linked to true if record exists' do
          Mobile::User.create(icn: user.icn, vet360_link_attempts: 1, vet360_linked: false)
          post '/mobile/v0/user/logged-in', headers: sis_headers
          expect(Mobile::User.where(icn: user.icn, vet360_link_attempts: 1, vet360_linked: true)).to exist
        end
      end

      context 'when user does not have a vet360_id' do
        let!(:user) { sis_user(vet360_id: nil) }

        it 'enqueues vet360 linking job' do
          expect(Mobile::V0::Vet360LinkingJob).to receive(:perform_async)
          post '/mobile/v0/user/logged-in', headers: sis_headers
        end
      end
    end
  end
end
