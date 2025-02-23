# frozen_string_literal: true

require 'rails_helper'
require 'evss/disability_compensation_auth_headers' # required to build a Form526Submission

RSpec.describe CentralMail::SubmitForm4142Job, type: :job do
  subject { described_class }

  before do
    Sidekiq::Job.clear_all
  end

  let(:user) { FactoryBot.create(:user, :loa3) }
  let(:auth_headers) do
    EVSS::DisabilityCompensationAuthHeaders.new(user).add_headers(EVSS::AuthHeaders.new(user).to_h)
  end
  let(:evss_claim_id) { 123_456_789 }
  let(:saved_claim) { FactoryBot.create(:va526ez) }

  describe '.perform_async' do
    let(:form_json) do
      File.read('spec/support/disability_compensation_form/submissions/with_4142.json')
    end
    let(:submission) do
      Form526Submission.create(user_uuid: user.uuid,
                               auth_headers_json: auth_headers.to_json,
                               saved_claim_id: saved_claim.id,
                               form_json:,
                               submitted_claim_id: evss_claim_id)
    end
    let(:metadata_hash) do
      form4142 = submission.form[Form526Submission::FORM_4142]
      form4142['veteranFullName'].update('first' => "Bey'oncé", 'last' => 'Knowle$-Carter')
      form4142['veteranAddress'].update('postalCode' => '123456789')
      subject.perform_async(submission.id)
      jid = subject.jobs.last['jid']
      processor = EVSS::DisabilityCompensationForm::Form4142Processor.new(submission, jid)
      request_body = processor.request_body
      JSON.parse(request_body['metadata'])
    end

    context 'with a successful submission job' do
      it 'queues a job for submit' do
        expect do
          subject.perform_async(submission.id)
        end.to change(subject.jobs, :size).by(1)
      end

      it 'submits successfully' do
        VCR.use_cassette('central_mail/submit_4142') do
          subject.perform_async(submission.id)
          jid = subject.jobs.last['jid']
          described_class.drain
          expect(jid).not_to be_empty
        end
      end

      it 'corrects for invalid characters in generated metadata' do
        veteran_first_name = metadata_hash['veteranFirstName']
        veteran_last_name = metadata_hash['veteranLastName']
        allowed_chars_regex = %r{^[a-zA-Z\/\-\s]}
        expect(veteran_first_name).to match(allowed_chars_regex)
        expect(veteran_last_name).to match(allowed_chars_regex)
      end

      it 'reformats zip code in generated metadata' do
        zip_code = metadata_hash['zipCode']
        expected_zip_format = /\A[0-9]{5}(?:-[0-9]{4})?\z/
        expect(zip_code).to match(expected_zip_format)
      end
    end

    context 'with a submission timeout' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_raise(Faraday::TimeoutError)
      end

      it 'raises a gateway timeout error' do
        subject.perform_async(submission.id)
        expect { described_class.drain }.to raise_error(Common::Exceptions::GatewayTimeout)
      end
    end

    context 'with an unexpected error' do
      before do
        allow_any_instance_of(Faraday::Connection).to receive(:post).and_raise(StandardError.new('foo'))
      end

      it 'raises a standard error' do
        subject.perform_async(submission.id)
        expect { described_class.drain }.to raise_error(StandardError)
      end
    end
  end

  describe '.perform_async for client error' do
    let(:missing_postalcode_form_json) do
      File.read 'spec/support/disability_compensation_form/submissions/with_4142_missing_postalcode.json'
    end
    let(:submission) do
      Form526Submission.create(user_uuid: user.uuid,
                               auth_headers_json: auth_headers.to_json,
                               saved_claim_id: saved_claim.id,
                               form_json: missing_postalcode_form_json,
                               submitted_claim_id: evss_claim_id)
    end

    context 'with a client error' do
      it 'raises a central mail response error' do
        VCR.use_cassette('central_mail/submit_4142_400') do
          subject.perform_async(submission.id)
          expect { described_class.drain }.to raise_error(CentralMail::SubmitForm4142Job::CentralMailResponseError)
        end
      end
    end
  end

  context 'catastrophic failure state' do
    describe 'when all retries are exhausted' do
      let!(:form526_submission) { create(:form526_submission) }
      let!(:form526_job_status) { create(:form526_job_status, :retryable_error, form526_submission:, job_id: 1) }

      it 'updates a StatsD counter and updates the status on an exhaustion event' do
        subject.within_sidekiq_retries_exhausted_block({ 'jid' => form526_job_status.job_id }) do
          expect(StatsD).to receive(:increment).with("#{subject::STATSD_KEY_PREFIX}.exhausted")
          expect(Rails).to receive(:logger).and_call_original
        end
        form526_job_status.reload
        expect(form526_job_status.status).to eq(Form526JobStatus::STATUS[:exhausted])
      end
    end
  end
end
