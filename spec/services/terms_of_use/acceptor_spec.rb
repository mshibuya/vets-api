# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TermsOfUse::Acceptor, type: :service do
  describe '#perform!' do
    subject(:acceptor) { described_class.new(user_account:, common_name:, version:) }

    let(:user_account) { create(:user_account, icn:) }
    let(:icn) { '123456789' }
    let(:version) { 'v1' }
    let(:common_name) { 'some-common-name' }

    describe 'validations' do
      context 'when all attributes are present' do
        it 'is valid' do
          expect(acceptor).to be_valid
        end
      end

      context 'when attributes are missing' do
        before do
          allow(Rails.logger).to receive(:error)
        end

        let(:expected_log) do
          "[TermsOfUse] [Acceptor] Error: #{expected_error_message}"
        end

        context 'when user_account is missing' do
          let(:user_account) { nil }
          let(:expected_error_message) { 'Validation failed: User account can\'t be blank, Icn can\'t be blank' }

          it 'is not valid' do
            expect { acceptor }.to raise_error(TermsOfUse::Errors::AcceptorError).with_message(expected_error_message)
            expect(Rails.logger).to have_received(:error).with(expected_log, { user_account_id: nil })
          end
        end

        context 'when common_name is missing' do
          let(:common_name) { nil }
          let(:expected_error_message) { 'Validation failed: Common name can\'t be blank' }

          it 'is not valid' do
            expect { acceptor }.to raise_error(TermsOfUse::Errors::AcceptorError).with_message(expected_error_message)
            expect(Rails.logger).to have_received(:error).with(expected_log, { user_account_id: user_account.id })
          end
        end

        context 'when version is missing' do
          let(:version) { nil }
          let(:expected_error_message) { 'Validation failed: Version can\'t be blank' }

          it 'is not valid' do
            expect { acceptor }.to raise_error(TermsOfUse::Errors::AcceptorError).with_message(expected_error_message)
            expect(Rails.logger).to have_received(:error).with(expected_log, { user_account_id: user_account.id })
          end
        end

        context 'when icn is missing' do
          let(:icn) { nil }
          let(:expected_error_message) { 'Validation failed: Icn can\'t be blank' }

          it 'is not valid' do
            expect { acceptor }.to raise_error(TermsOfUse::Errors::AcceptorError).with_message(expected_error_message)
            expect(Rails.logger).to have_received(:error).with(expected_log, { user_account_id: user_account.id })
          end
        end
      end
    end

    describe '#perform!' do
      let(:expected_attr_key) do
        Digest::SHA256.hexdigest({ icn:, signature_name: common_name, version: }.to_json)
      end

      before do
        allow(TermsOfUse::SignUpServiceUpdaterJob).to receive(:perform_async)
      end

      it 'creates a new terms of use agreement with the given version' do
        expect { acceptor.perform! }.to change { user_account.terms_of_use_agreements.count }.by(1)
        expect(user_account.terms_of_use_agreements.last.agreement_version).to eq(version)
      end

      it 'marks the terms of use agreement as accepted' do
        expect(acceptor.perform!).to be_accepted
      end

      it 'enqueues the SignUpServiceUpdaterJob with expected parameters' do
        acceptor.perform!
        expect(TermsOfUse::SignUpServiceUpdaterJob).to have_received(:perform_async).with(expected_attr_key)
      end
    end
  end
end
