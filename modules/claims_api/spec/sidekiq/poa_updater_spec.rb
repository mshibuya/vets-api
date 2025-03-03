# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ClaimsApi::PoaUpdater, type: :job do
  subject { described_class }

  before do
    Sidekiq::Job.clear_all
  end

  let(:user) { FactoryBot.create(:user, :loa3) }
  let(:auth_headers) do
    headers = EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
    headers['va_eauth_pnid'] = '796104437'
    headers
  end

  context "when call to BGS 'update_birls_record' is successful" do
    context 'and record consent is granted' do
      it "updates the form's status and creates 'ClaimsApi::PoaVBMSUpdater' job" do
        create_mock_lighthouse_service
        expect(ClaimsApi::PoaVBMSUpdater).to receive(:perform_async)

        poa = create_poa
        poa.form_data.merge!({ recordConsent: true, consentLimits: [] })
        poa.save!

        subject.new.perform(poa.id)
        poa.reload
        expect(poa.status).to eq('updated')
      end
    end

    context 'and record consent is not granted' do
      context "because 'recordConsent' is false" do
        it "updates the form's status but does not create a 'ClaimsApi::PoaVBMSUpdater' job" do
          create_mock_lighthouse_service
          expect(ClaimsApi::PoaVBMSUpdater).not_to receive(:perform_async)

          poa = create_poa
          poa.form_data.merge!({ recordConsent: false, consentLimits: [] })
          poa.save!

          subject.new.perform(poa.id)
          poa.reload
          expect(poa.status).to eq('updated')
        end
      end

      context "because a limitation exists in 'consentLimits'" do
        it "updates the form's status but does not create a 'ClaimsApi::PoaVBMSUpdater' job" do
          create_mock_lighthouse_service
          expect(ClaimsApi::PoaVBMSUpdater).not_to receive(:perform_async)

          poa = create_poa
          poa.form_data.merge!({ recordConsent: true, consentLimits: %w[ALCOHOLISM] })
          poa.save!

          subject.new.perform(poa.id)
          poa.reload
          expect(poa.status).to eq('updated')
        end
      end
    end
  end

  context "when call to BGS 'update_birls_record' fails" do
    it "updates the form's status and does not create a 'ClaimsApi::PoaVBMSUpdater' job" do
      create_mock_lighthouse_service
      allow_any_instance_of(BGS::VetRecordWebService).to receive(:update_birls_record).and_return(
        return_code: 'some error code'
      )
      expect(ClaimsApi::PoaVBMSUpdater).not_to receive(:perform_async)

      poa = create_poa

      subject.new.perform(poa.id)
      poa.reload
      expect(poa.status).to eq('errored')
    end
  end

  private

  def create_poa
    poa = create(:power_of_attorney)
    poa.auth_headers = auth_headers
    poa.save
    poa
  end

  def create_mock_lighthouse_service
    allow_any_instance_of(BGS::PersonWebService).to receive(:find_by_ssn).and_return({ file_nbr: '123456789' })
    allow_any_instance_of(BGS::VetRecordWebService).to receive(:update_birls_record)
      .and_return({ return_code: 'BMOD0001' })
  end
end
