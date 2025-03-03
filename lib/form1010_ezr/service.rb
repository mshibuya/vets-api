# frozen_string_literal: true

require 'common/client/base'
require 'hca/enrollment_system'
require 'hca/configuration'
require 'hca/ezr_postfill'
require 'va1010_forms/utils'

module Form1010Ezr
  class Service < Common::Client::Base
    include Common::Client::Concerns::Monitoring
    include VA1010Forms::Utils
    include SentryLogging

    STATSD_KEY_PREFIX = 'api.1010ezr'

    # Due to using the same endpoint as the 10-10EZ (HealthCareApplication), we
    # can utilize the same client configuration
    configuration HCA::Configuration

    FORM_ID = '10-10EZR'

    # @param [Object] user
    def initialize(user)
      super()
      @user = user
    end

    def submit_async(parsed_form)
      HCA::EzrSubmissionJob.perform_async(
        HealthCareApplication::LOCKBOX.encrypt(parsed_form.to_json),
        HealthCareApplication.get_user_identifier(@user)
      )
    end

    def submit_sync(parsed_form)
      formatted = HCA::EnrollmentSystem.veteran_to_save_submit_form(parsed_form, @user, FORM_ID)
      content = Gyoku.xml(formatted)
      submission = soap.build_request(:save_submit_form, message: content)
      response = with_monitoring do
        perform(:post, '', submission.body)
      rescue => e
        increment_failure('submit_form', e)
        raise e
      ensure
        increment_total('submit_form')
      end

      root = response.body.locate('S:Envelope/S:Body/submitFormResponse').first
      form_submission_id = root.locate('formSubmissionId').first.text.to_i

      # Log the 'formSubmissionId' for successful submissions
      Rails.logger.info("SubmissionID=#{form_submission_id}")

      {
        success: true,
        formSubmissionId: form_submission_id,
        timestamp: root.locate('timeStamp').first&.text || Time.now.getlocal.to_s
      }
    end

    # @param [HashWithIndifferentAccess] parsed_form JSON form data
    def submit_form(parsed_form)
      parsed_form = configure_and_validate_form(parsed_form)
      if Flipper.enabled?(:ezr_async, @user)
        submit_async(parsed_form)
      else
        submit_sync(parsed_form)
      end
    rescue => e
      log_submission_failure(parsed_form)
      Rails.logger.error "10-10EZR form submission failed: #{e.message}"
      raise e
    end

    def log_submission_failure(parsed_form)
      StatsD.increment("#{Form1010Ezr::Service::STATSD_KEY_PREFIX}.failed_wont_retry")

      if parsed_form.present?
        PersonalInformationLog.create!(
          data: parsed_form,
          error_class: 'Form1010Ezr FailedWontRetry'
        )

        log_message_to_sentry(
          '1010EZR total failure',
          :error,
          {
            first_initial: parsed_form['veteranFullName']['first'][0],
            middle_initial: parsed_form['veteranFullName']['middle'].try(:[], 0),
            last_initial: parsed_form['veteranFullName']['last'][0]
          },
          ezr: :total_failure
        )
      end
    end

    private

    # Compare the 'parsed_form' to the JSON form schema in vets-json-schema
    def validate_form(parsed_form)
      schema = VetsJsonSchema::SCHEMAS[FORM_ID]
      # @return [Array<String>] array of strings detailing schema validation failures
      validation_errors = JSON::Validator.fully_validate(schema, parsed_form)

      if validation_errors.present?
        log_validation_errors(parsed_form)

        Rails.logger.error('10-10EZR form validation failed. Form does not match schema.')
        raise Common::Exceptions::SchemaValidationErrors, validation_errors
      end
    end

    # Add required fields not included in the JSON schema, but are
    # required in the Enrollment System API
    def post_fill_required_fields(parsed_form)
      required_fields = HCA::EzrPostfill.post_fill_hash(@user)

      parsed_form.merge!(required_fields)
    end

    def configure_and_validate_form(parsed_form)
      post_fill_required_fields(parsed_form)
      validate_form(parsed_form)
      # Due to overriding the JSON form schema, we need to do so after the form has been validated
      override_parsed_form(parsed_form)
      add_financial_flag(parsed_form)
    end

    def add_financial_flag(parsed_form)
      if parsed_form['veteranGrossIncome'].present?
        parsed_form.merge('discloseFinancialInformation' => true)
      else
        parsed_form
      end
    end

    def log_validation_errors(parsed_form)
      StatsD.increment("#{Form1010Ezr::Service::STATSD_KEY_PREFIX}.validation_error")

      PersonalInformationLog.create(
        data: parsed_form,
        error_class: 'Form1010Ezr ValidationError'
      )
    end
  end
end
