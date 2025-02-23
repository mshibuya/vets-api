# frozen_string_literal: true

require 'central_mail/service'
require 'benefits_intake_service/service'
require 'central_mail/datestamp_pdf'
require 'pdf_info'

module CentralMail
  class SubmitCentralForm686cJob
    include Sidekiq::Job
    include SentryLogging

    FOREIGN_POSTALCODE = '00000'
    FORM_ID = '686C-674'

    sidekiq_options retry: false

    attr_reader :claim, :form_path, :attachment_paths

    class CentralMailResponseError < StandardError; end

    def extract_uuid_from_central_mail_message(data)
      data.body[/(?<=\[).*?(?=\])/].split(': ').last if data.body.present?
    end

    def perform(saved_claim_id, encrypted_vet_info, encrypted_user_struct)
      vet_info = JSON.parse(KmsEncrypted::Box.new.decrypt(encrypted_vet_info))
      user_struct = JSON.parse(KmsEncrypted::Box.new.decrypt(encrypted_user_struct))
      # if the 686c-674 has failed we want to call this central mail job (credit to submit_saved_claim_job.rb)
      # have to re-find the claim and add the relevant veteran info
      Rails.logger.info('CentralMail::SubmitCentralForm686cJob running!',
                        { user_uuid: user_struct['uuid'], saved_claim_id:, icn: user_struct['icn'] })
      @claim = SavedClaim::DependencyClaim.find(saved_claim_id)
      claim.add_veteran_info(vet_info)

      get_files_from_claim

      use_lighthouse = Flipper.enabled?(:dependents_central_submission_lighthouse)
      result = use_lighthouse ? upload_to_lh : CentralMail::Service.new.upload(create_request_body)
      check_success(result, saved_claim_id, user_struct)
    rescue => e
      # if we fail, update the associated central mail record to failed and send the user the failure email
      Rails.logger.warn('CentralMail::SubmitCentralForm686cJob failed!',
                        { user_uuid: user_struct['uuid'], saved_claim_id:, icn: user_struct['icn'], error: e.message })
      update_submission('failed')
      DependentsApplicationFailureMailer.build(OpenStruct.new(user_struct)).deliver_now if user_struct['email'].present?
      raise
    ensure
      cleanup_file_paths
    end

    def upload_to_lh
      Rails.logger.info({ message: 'SubmitCentralForm686cJob Lighthouse Initiate Submission Attempt',
                          claim_id: claim.id })
      lighthouse_service = BenefitsIntakeService::Service.new(with_upload_location: true)
      uuid = lighthouse_service.uuid
      Rails.logger.info({ message: 'SubmitCentralForm686cJob Lighthouse Submission Attempt', claim_id: claim.id,
                          uuid: })
      response = lighthouse_service.upload_form(
        main_document: split_file_and_path(form_path),
        attachments: attachment_paths.map(&method(:split_file_and_path)),
        form_metadata: generate_metadata_lh
      )
      Rails.logger.info({ message: 'SubmitCentralForm686cJob Lighthouse Submission Successful', claim_id: claim.id,
                          uuid: })
      response
    end

    def get_files_from_claim
      # process the main pdf record and the attachments as we would for a vbms submission
      form_674_path = process_pdf(claim.to_pdf(form_id: '21-674')) if claim.submittable_674?
      form_686c_path = process_pdf(claim.to_pdf(form_id: '686C-674')) if claim.submittable_686?
      @form_path = form_686c_path || form_674_path
      @attachment_paths = claim.persistent_attachments.map { |pa| process_pdf(pa.to_pdf) }
      # Treat 674 as first attachment
      attachment_paths.insert(0, form_674_path) if form_686c_path.present? && form_674_path.present?
    end

    def cleanup_file_paths
      Common::FileHelpers.delete_file_if_exists(form_path)
      attachment_paths.each { |p| Common::FileHelpers.delete_file_if_exists(p) }
    end

    # rubocop:disable Metrics/MethodLength #Temporary disable until flipper removed
    def check_success(response, saved_claim_id, user_struct)
      if Flipper.enabled?(:dependents_central_submission_lighthouse)
        if response.success?
          Rails.logger.info('CentralMail::SubmitCentralForm686cJob succeeded!',
                            { user_uuid: user_struct['uuid'], saved_claim_id:, icn: user_struct['icn'] })
          update_submission('success')
          send_confirmation_email(OpenStruct.new(user_struct))
        else
          Rails.logger.info('CentralMail::SubmitCentralForm686cJob Unsuccessful',
                            { response: response['message'].presence || response['errors'] })
          raise CentralMailResponseError
        end
      elsif response.success?
        Rails.logger.info('CentralMail::SubmitCentralForm686cJob succeeded!',
                          { user_uuid: user_struct['uuid'], saved_claim_id:, icn: user_struct['icn'],
                            centralmail_uuid: extract_uuid_from_central_mail_message(response) })
        update_submission('success')
        send_confirmation_email(OpenStruct.new(user_struct))
      else
        Rails.logger.info('CentralMail::SubmitCentralForm686cJob Unsuccessful',
                          { response: response.body })
        raise CentralMailResponseError
      end
    end

    # rubocop:enable Metrics/MethodLength

    def create_request_body
      body = {
        'metadata' => generate_metadata.to_json
      }

      body['document'] = to_faraday_upload(form_path)

      i = 0
      attachment_paths.each do |file_path|
        body["attachment#{i += 1}"] = to_faraday_upload(file_path)
      end

      body
    end

    def update_submission(state)
      claim.central_mail_submission.update!(state:) if claim.respond_to?(:central_mail_submission)
    end

    def to_faraday_upload(file_path)
      Faraday::UploadIO.new(
        file_path,
        Mime[:pdf].to_s
      )
    end

    def process_pdf(pdf_path)
      stamped_path1 = CentralMail::DatestampPdf.new(pdf_path).run(text: 'VA.GOV', x: 5, y: 5)
      CentralMail::DatestampPdf.new(stamped_path1).run(
        text: 'FDC Reviewed - va.gov Submission',
        x: 429,
        y: 770,
        text_only: true
      )
    end

    def get_hash_and_pages(file_path)
      {
        hash: Digest::SHA256.file(file_path).hexdigest,
        pages: PdfInfo::Metadata.read(file_path).pages
      }
    end

    def generate_metadata
      form = claim.parsed_form['dependents_application']
      form_pdf_metadata = get_hash_and_pages(form_path)
      address = form['veteran_contact_information']['veteran_address']
      receive_date = claim.created_at.in_time_zone('Central Time (US & Canada)')
      metadata = {
        'veteranFirstName' => form['veteran_information']['full_name']['first'],
        'veteranLastName' => form['veteran_information']['full_name']['last'],
        'fileNumber' => form['veteran_information']['file_number'] || form['veteran_information']['ssn'],
        'receiveDt' => receive_date.strftime('%Y-%m-%d %H:%M:%S'),
        'uuid' => claim.guid,
        'zipCode' => address['country_name'] == 'USA' ? address['zip_code'] : FOREIGN_POSTALCODE,
        'source' => 'va.gov',
        'hashV' => form_pdf_metadata[:hash],
        'numberAttachments' => attachment_paths.size,
        'docType' => claim.form_id,
        'numberPages' => form_pdf_metadata[:pages]
      }
      metadata.merge(generate_attachment_metadata(attachment_paths))
    end

    def generate_metadata_lh
      form = claim.parsed_form['dependents_application']
      address = form['veteran_contact_information']['veteran_address']
      {
        veteran_first_name: form['veteran_information']['full_name']['first'],
        veteran_last_name: form['veteran_information']['full_name']['last'],
        file_number: form['veteran_information']['file_number'] || form['veteran_information']['ssn'],
        zip: address['country_name'] == 'USA' ? address['zip_code'] : FOREIGN_POSTALCODE,
        doc_type: claim.form_id,
        claim_date: claim.created_at
      }
    end

    def generate_attachment_metadata(attachment_paths)
      attachment_metadata = {}
      i = 0
      attachment_paths.each do |file_path|
        i += 1
        attachment_pdf_metadata = get_hash_and_pages(file_path)
        attachment_metadata["ahash#{i}"] = attachment_pdf_metadata[:hash]
        attachment_metadata["numberPages#{i}"] = attachment_pdf_metadata[:pages]
      end
      attachment_metadata
    end

    def send_confirmation_email(user)
      return if user.va_profile_email.blank?

      VANotify::ConfirmationEmail.send(
        email_address: user.va_profile_email,
        template_id: Settings.vanotify.services.va_gov.template_id.form686c_confirmation_email,
        first_name: user&.first_name&.upcase,
        user_uuid_and_form_id: "#{user.uuid}_#{FORM_ID}"
      )
    end

    private

    def log_cmp_response(response)
      log_message_to_sentry("vre-central-mail-response: #{response}", :info, {}, { team: 'vfs-ebenefits' })
    end

    def valid_claim_data(saved_claim_id, vet_info)
      claim = SavedClaim::DependencyClaim.find(saved_claim_id)

      claim.add_veteran_info(vet_info)

      raise Invalid686cClaim unless claim.valid?(:run_686_form_jobs)

      claim.formatted_686_data(vet_info)
    end

    def split_file_and_path(path)
      { file: path, file_name: path.split('/').last }
    end
  end
end
