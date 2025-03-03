# frozen_string_literal: true

module EVSS
  module DisabilityCompensationForm
    class SubmitUploads < Job
      STATSD_KEY_PREFIX = 'worker.evss.submit_form526_upload'

      # retry for one day
      sidekiq_options retry: 14

      sidekiq_retries_exhausted do |msg, _ex|
        job_id = msg['jid']
        error_class = msg['error_class']
        error_message = msg['error_message']
        timestamp = Time.now.utc
        form526_submission_id = msg['args'].first

        form_job_status = Form526JobStatus.find_by(job_id:)
        bgjob_errors = form_job_status.bgjob_errors || {}
        new_error = {
          "#{timestamp.to_i}": {
            caller_method: __method__.to_s,
            error_class:,
            error_message:,
            timestamp:,
            form526_submission_id:
          }
        }
        form_job_status.update(
          status: Form526JobStatus::STATUS[:exhausted],
          bgjob_errors: bgjob_errors.merge(new_error)
        )

        StatsD.increment("#{STATSD_KEY_PREFIX}.exhausted")

        ::Rails.logger.warn(
          'Submit Form 526 Upload Retries exhausted',
          { job_id:, error_class:, error_message:, timestamp:, form526_submission_id: }
        )
      rescue => e
        ::Rails.logger.error(
          'Failure in SubmitUploads#sidekiq_retries_exhausted',
          {
            messaged_content: e.message,
            job_id:,
            submission_id: form526_submission_id,
            pre_exhaustion_failure: {
              error_class:,
              error_message:
            }
          }
        )
        raise e
      end

      # Recursively submits a file in a new instance of this job for each upload in the uploads list
      #
      # @param submission_id [Integer] The {Form526Submission} id
      # @param upload_data [String] upload GUID in AWS S3
      #
      def perform(submission_id, upload_data)
        Sentry.set_tags(source: '526EZ-all-claims')
        super(submission_id)
        upload_data = upload_data.first if upload_data.is_a?(Array) # temporary for transition
        guid = upload_data&.dig('confirmationCode')
        with_tracking("Form526 Upload: #{guid}", submission.saved_claim_id, submission.id) do
          sea = SupportingEvidenceAttachment.find_by(guid:)
          file_body = sea&.get_file&.read

          raise ArgumentError, "supporting evidence attachment with guid #{guid} has no file data" if file_body.nil?

          document_data = create_document_data(upload_data, sea.converted_filename)
          raise Common::Exceptions::ValidationErrors, document_data unless document_data.valid?

          if Flipper.enabled?(:disability_compensation_lighthouse_document_service_provider)
            # TODO: create client from lighthouse document service
          else
            client = EVSS::DocumentsService.new(submission.auth_headers)
          end
          client.upload(file_body, document_data)
        end
      rescue => e
        # Can't send a job manually to the dead set.
        # Log and re-raise so the job ends up in the dead set and the parent batch is not marked as complete.
        retryable_error_handler(e)
      end

      private

      def retryable_error_handler(error)
        super(error)
        raise error
      end

      def create_document_data(upload_data, converted_filename)
        EVSSClaimDocument.new(
          evss_claim_id: submission.submitted_claim_id,
          file_name: converted_filename || upload_data['name'],
          tracked_item_id: nil,
          document_type: upload_data['attachmentId']
        )
      end
    end
  end
end
