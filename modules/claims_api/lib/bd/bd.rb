# frozen_string_literal: true

require 'faraday'
require 'claims_api/v2/benefits_documents/service'

module ClaimsApi
  ##
  # Class to interact with the BRD API
  #
  class BD
    def initialize
      @multipart = false
      @use_mock = Settings.claims_api.benefits_documents.use_mocks || false
    end

    ##
    # Search documents by claim and file number
    #
    # @return Documents list
    def search(claim_id, file_number)
      @multipart = false
      body = { data: { claimId: claim_id, fileNumber: file_number } }
      ClaimsApi::Logger.log('benefits_documents',
                            detail: "calling benefits documents search for claimId #{claim_id}")
      client.post('documents/search', body)&.body&.deep_symbolize_keys
    rescue => e
      ClaimsApi::Logger.log('benefits_documents',
                            detail: "/search failure for claimId #{claim_id}, #{e.message}")
      {}
    end

    ##
    # Upload document of mapped claim
    #
    # @return success or failure
    def upload(claim:, pdf_path:, doc_type: 'L122', file_number: nil)
      unless File.exist? pdf_path
        ClaimsApi::Logger.log('526', detail: "Error uploading doc to BD: #{pdf_path} doesn't exist", claim_id: claim.id)
        raise Errno::ENOENT, pdf_path
      end

      @multipart = true
      body = generate_upload_body(claim:, doc_type:, pdf_path:, file_number:)
      res = client.post('documents', body)&.body&.deep_symbolize_keys
      request_id = res&.dig(:data, :requestId)
      ClaimsApi::Logger.log('526', detail: 'Successfully uploaded doc to BD', claim_id: claim.id, request_id:)
      res
    end

    private

    ##
    # Generate form body to upload a document
    #
    # @return {parameters, file}
    def generate_upload_body(claim:, doc_type:, pdf_path:, file_number: nil)
      payload = {}
      veteran_name = "#{claim.auth_headers['va_eauth_firstName']}_#{claim.auth_headers['va_eauth_lastName']}"
      file_name = "526EZ_#{veteran_name}_#{claim.evss_id}.pdf"
      data = {
        data: {
          systemName: 'VA.gov',
          docType: doc_type,
          claimId: claim.evss_id,
          fileNumber: file_number || claim.auth_headers['va_eauth_birlsfilenumber'],
          fileName: file_name,
          trackedItemIds: []
        }
      }
      fn = Tempfile.new('params')
      File.write(fn, data.to_json)
      payload[:parameters] = Faraday::UploadIO.new(fn, 'application/json')
      payload[:file] = Faraday::UploadIO.new(pdf_path, 'application/pdf')
      payload
    end

    ##
    # Configure Faraday base class (and do auth)
    #
    # @return Faraday client
    def client
      base_name = if Settings.claims_api&.benefits_documents&.host.nil?
                    'https://api.va.gov/services'
                  else
                    "#{Settings.claims_api&.benefits_documents&.host}/services"
                  end

      @token ||= ClaimsApi::V2::BenefitsDocuments::Service.new.get_auth_token
      raise StandardError, 'Benefits Docs token missing' if @token.blank? && !@use_mock

      Faraday.new("#{base_name}/benefits-documents/v1",
                  headers: { 'Authorization' => "Bearer #{@token}" }) do |f|
        f.request @multipart ? :multipart : :json
        f.response :betamocks if @use_mock
        f.response :raise_error
        f.response :json, parser_options: { symbolize_names: true }
        f.adapter Faraday.default_adapter
      end
    end
  end
end
