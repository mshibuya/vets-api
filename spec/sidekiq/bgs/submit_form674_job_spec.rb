# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BGS::SubmitForm674Job, type: :job do
  let(:user) { FactoryBot.create(:evss_user, :loa3) }
  let(:dependency_claim) { create(:dependency_claim) }
  let(:all_flows_payload) { FactoryBot.build(:form_686c_674_kitchen_sink) }
  let(:birth_date) { '1809-02-12' }
  let(:client_stub) { instance_double(BGS::Form674) }
  let(:vet_info) do
    {
      'veteran_information' => {
        'full_name' => {
          'first' => 'WESLEY', 'middle' => nil, 'last' => 'FORD'
        },
        'common_name' => user.common_name,
        'participant_id' => '600061742',
        'uuid' => user.uuid,
        'email' => user.email,
        'va_profile_email' => user.va_profile_email,
        'ssn' => '796043735',
        'va_file_number' => '796043735',
        'icn' => user.icn,
        'birth_date' => birth_date
      }
    }
  end
  let(:user_struct) do
    nested_info = vet_info['veteran_information']
    OpenStruct.new(
      first_name: nested_info['full_name']['first'],
      last_name: nested_info['full_name']['last'],
      middle_name: nested_info['full_name']['middle'],
      ssn: nested_info['ssn'],
      email: nested_info['email'],
      va_profile_email: nested_info['va_profile_email'],
      participant_id: nested_info['participant_id'],
      icn: nested_info['icn'],
      uuid: nested_info['uuid'],
      common_name: nested_info['common_name']
    )
  end

  context 'success' do
    before do
      expect(BGS::Form674).to receive(:new).with(user_struct, dependency_claim).and_return(client_stub)
      expect(client_stub).to receive(:submit).once
    end

    it 'successfully calls #submit for 674 submission' do
      expect(OpenStruct).to receive(:new)
        .with(hash_including(user_struct.to_h))
        .and_return(user_struct)
      expect do
        subject.perform(user.uuid, user.icn, dependency_claim.id, vet_info, user_struct.to_h)
      end.not_to raise_error
    end

    it 'successfully calls #submit without a user_struct passed in by 686c' do
      expect(OpenStruct).to receive(:new)
        .with(hash_including(icn: vet_info['veteran_information']['icn']))
        .and_return(user_struct)
      expect do
        subject.perform(user.uuid, user.icn, dependency_claim.id, vet_info)
      end.not_to raise_error
    end

    it 'sends confirmation email' do
      expect(OpenStruct).to receive(:new)
        .with(hash_including(icn: vet_info['veteran_information']['icn']))
        .and_return(user_struct)
      expect(VANotify::EmailJob).to receive(:perform_async).with(
        user.va_profile_email,
        'fake_template_id',
        {
          'date' => Time.now.in_time_zone('Eastern Time (US & Canada)').strftime('%B %d, %Y'),
          'first_name' => 'WESLEY'
        }
      )

      subject.perform(user.uuid, user.icn, dependency_claim.id, vet_info, user_struct.to_h)
    end
  end

  context 'error with central submission' do
    before do
      allow(OpenStruct).to receive(:new).and_call_original
      InProgressForm.create!(form_id: '686C-674', user_uuid: user.uuid, form_data: all_flows_payload)
    end

    it 'raises error' do
      expect(OpenStruct).to receive(:new)
        .with(hash_including(icn: vet_info['veteran_information']['icn']))
        .and_return(user_struct)
      expect(BGS::Form674).to receive(:new).with(user_struct, dependency_claim) { client_stub }
      expect(client_stub).to receive(:submit).and_raise(BGS::SubmitForm674Job::Invalid674Claim)

      expect do
        subject.perform(user.uuid, user.icn, dependency_claim.id, vet_info, user_struct.to_h)
      end.to raise_error(BGS::SubmitForm674Job::Invalid674Claim)
    end
  end
end
