# frozen_string_literal: true

require 'sidekiq/form526_backup_submission_process/processor'

module Sidekiq
  module Form526BackupSubmissionProcess
    class Form526BackgroundLoader
      extend ActiveSupport::Concern
      include Sidekiq::Job
      sidekiq_options retry: false

      def perform(id)
        Processor.new(id, get_upload_location_on_instantiation: false,
                          ignore_expiration: true).upload_pdf_submission_to_s3
      end
    end

    class Submit
      extend ActiveSupport::Concern
      include SentryLogging
      include Sidekiq::Job

      sidekiq_options retry: 14
      STATSD_KEY_PREFIX = 'worker.evss.form526_backup_submission_process'

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
          'Form 526 Backup Submission Retries exhausted',
          { job_id:, error_class:, error_message:, timestamp:, form526_submission_id: }
        )
      rescue => e
        ::Rails.logger.error(
          'Failure in Form526BackupSubmission#sidekiq_retries_exhausted',
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

      def perform(form526_submission_id)
        return unless Settings.form526_backup.enabled

        job_status = Form526JobStatus.find_or_initialize_by(job_id: jid)
        job_status.assign_attributes(form526_submission_id:,
                                     job_class: 'BackupSubmission',
                                     status: 'pending')
        job_status.save!

        Processor.new(form526_submission_id).process!
        job_status.update(status: Form526JobStatus::STATUS[:success])
      rescue => e
        ::Rails.logger.error(
          message: "FORM526 BACKUP SUBMISSION FAILURE. Investigate immediately: #{e.message}.",
          backtrace: e.backtrace,
          submission_id: form526_submission_id
        )
        bgjob_errors = job_status.bgjob_errors || {}
        bgjob_errors.merge!(error_hash_for_job_status(e))
        job_status.update(status: Form526JobStatus::STATUS[:retryable_error], bgjob_errors:)
        raise e
      end

      private

      def error_hash_for_job_status(e)
        timestamp = Time.zone.now
        {
          "#{timestamp.to_i}": {
            caller_method: __method__.to_s,
            error_class: e.class.to_s,
            error_message: e.message,
            timestamp:
          }
        }
      end
    end
  end
end
