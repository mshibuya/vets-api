# frozen_string_literal: true

require 'pdf_fill/filler'
require 'central_mail/datestamp_pdf'
require 'decision_review_v1/utilities/constants'
require 'simple_forms_api_submission/metadata_validator'

module DecisionReviewV1
  module Processor
    class Form4142Processor
      # @return [Pathname] the generated PDF path
      attr_reader :pdf_path

      # @return [Hash] the generated request body
      attr_reader :request_body

      def initialize(form_data:, submission_id: nil)
        @form = form_data
        @pdf_path = generate_stamp_pdf
        @uuid = SecureRandom.uuid
        @request_body = {
          'document' => to_faraday_upload,
          'metadata' => generate_metadata
        }
        @submission = Form526Submission.find_by(id: submission_id)
      end

      def generate_stamp_pdf
        pdf = PdfFill::Filler.fill_ancillary_form(
          @form, @uuid, FORM_ID
        )
        stamped_path = CentralMail::DatestampPdf.new(pdf).run(text: 'VA.gov', x: 5, y: 5,
                                                              timestamp: @submission&.created_at)
        CentralMail::DatestampPdf.new(stamped_path).run(
          text: 'VA.gov Submission',
          x: 510,
          y: 775,
          text_only: true,
          timestamp: @submission&.created_at
        )
      end

      private

      def to_faraday_upload
        Faraday::UploadIO.new(
          @pdf_path,
          Mime[:pdf].to_s
        )
      end

      def generate_metadata
        address = @form['veteranAddress']
        country_is_us = address['country'] == 'US'
        veteran_full_name = @form['veteranFullName']
        metadata = {
          'veteranFirstName' => veteran_full_name['first'],
          'veteranLastName' => veteran_full_name['last'],
          'fileNumber' => @form['vaFileNumber'] || @form['veteranSocialSecurityNumber'],
          'receiveDt' => received_date,
          # 'uuid' => "#{@uuid}_4142", # was trying to include the main claim uuid here and just append 4142
          # but central mail portal does not support that
          'uuid' => @uuid,
          'zipCode' => address['postalCode'],
          'source' => 'VA Forms Group B',
          'hashV' => Digest::SHA256.file(@pdf_path).hexdigest,
          'numberAttachments' => 0,
          'docType' => FORM_ID,
          'numberPages' => PDF::Reader.new(@pdf_path).pages.size
        }

        SimpleFormsApiSubmission::MetadataValidator.validate(
          metadata, zip_code_is_us_based: country_is_us
        ).to_json
      end

      def received_date
        date = if @submission.nil?
                 Time.now.in_time_zone('Central Time (US & Canada)')
               else
                 @submission.created_at.in_time_zone('Central Time (US & Canada)')
               end
        date.strftime('%Y-%m-%d %H:%M:%S')
      end
    end
  end
end
