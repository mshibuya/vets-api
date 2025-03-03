# frozen_string_literal: true

require 'rails_helper'
require AppealsApi::Engine.root.join('spec', 'spec_helper.rb')

describe AppealsApi::V1::AppealsController, type: :request do
  include SchemaMatchers

  describe '#index' do
    let(:path) { '/services/appeals/v1/appeals' }
    let(:caseflow_cassette_name) { 'caseflow/appeals' }
    let(:mpi_cassette_name) { 'mpi/find_candidate/valid' }
    let(:va_user) { 'test.user@example.com' }
    let(:headers) { { 'X-Consumer-Username' => 'TestConsumer', 'X-VA-User' => va_user } }
    let(:icn) { '1012667145V762142' }
    let(:ssn) { '796122306' }

    describe 'ICN parameter handling' do
      it_behaves_like(
        'GET endpoint with optional Veteran ICN parameter',
        {
          cassette: 'caseflow/appeals',
          path: '/services/appeals/v1/appeals',
          scope_base: 'AppealsStatus',
          headers: { 'X-VA-User' => 'test.user@example.com' }
        }
      )
    end

    describe 'auth behavior' do
      it_behaves_like('an endpoint with OpenID auth', scopes: described_class::OAUTH_SCOPES[:GET]) do
        def make_request(auth_header)
          VCR.use_cassette(caseflow_cassette_name) do
            VCR.use_cassette(mpi_cassette_name) do
              get(path, params: { icn: }, headers: auth_header.merge(headers))
            end
          end
        end
      end
    end

    describe 'caseflow interaction' do
      let(:scopes) { %w[veteran/AppealsStatus.read] }
      let(:params) { {} }
      let(:error) { JSON.parse(response.body).dig('errors', 0) }

      before do
        allow(Rails.logger).to receive(:info)
        VCR.use_cassette(caseflow_cassette_name) do
          VCR.use_cassette(mpi_cassette_name) do
            with_openid_auth(scopes) { |auth_header| get(path, params:, headers: auth_header.merge(headers)) }
          end
        end
      end

      it 'logs the caseflow request and response' do
        expect(response).to match_response_schema('appeals')
        expect(Rails.logger).to have_received(:info).with(
          'Caseflow Request',
          { 'va_user' => va_user, 'lookup_identifier' => Digest::SHA2.hexdigest(ssn) }
        )
        expect(Rails.logger).to have_received(:info).with(
          'Caseflow Response',
          { 'va_user' => va_user, 'first_appeal_id' => '1196201', 'appeal_count' => 3 }
        )
      end

      describe 'when veteran is not found by SSN in caseflow' do
        let(:caseflow_cassette_name) { 'caseflow/not_found' }

        it 'returns a 404 error with a message that does not reference SSN' do
          expect(response).to have_http_status(:not_found)
          expect(error['detail']).not_to include('SSN')
        end
      end

      describe 'when caseflow throws a 500 error' do
        let(:caseflow_cassette_name) { 'caseflow/server_error' }

        it 'returns a 502 error instead' do
          expect(response).to have_http_status(:bad_gateway)
        end
      end
    end
  end
end
