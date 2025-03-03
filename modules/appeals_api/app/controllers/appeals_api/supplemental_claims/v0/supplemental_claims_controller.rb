# frozen_string_literal: true

require 'appeals_api/form_schemas'

module AppealsApi::SupplementalClaims::V0
  class SupplementalClaimsController < AppealsApi::ApplicationController
    include AppealsApi::CharacterUtilities
    include AppealsApi::IcnParameterValidation
    include AppealsApi::JsonFormatValidation
    include AppealsApi::MPIVeteran
    include AppealsApi::OpenidAuth
    include AppealsApi::PdfDownloads
    include AppealsApi::Schemas
    include AppealsApi::StatusSimulation

    skip_before_action :authenticate
    before_action :validate_json_body, if: -> { request.post? }
    before_action :validate_json_schema, only: %i[create validate]
    before_action :validate_icn_parameter, only: %i[index download]

    ALLOWED_COLUMNS = %i[id status code detail created_at updated_at].freeze
    API_VERSION = 'V0'
    FORM_NUMBER = '200995'
    MODEL_ERROR_STATUS = 422
    SCHEMA_OPTIONS = { schema_version: 'v0', api_name: 'supplemental_claims' }.freeze

    OAUTH_SCOPES = {
      GET: %w[veteran/SupplementalClaims.read representative/SupplementalClaims.read system/SupplementalClaims.read],
      PUT: %w[veteran/SupplementalClaims.write representative/SupplementalClaims.write system/SupplementalClaims.write],
      POST: %w[veteran/SupplementalClaims.write representative/SupplementalClaims.write system/SupplementalClaims.write]
    }.freeze

    def index
      veteran_scs = AppealsApi::SupplementalClaim.select(ALLOWED_COLUMNS)
                                                 .where(veteran_icn: params[:icn])
                                                 .order(created_at: :desc)
      render_supplemental_claim(veteran_scs)
    end

    def schema
      response = AppealsApi::JsonSchemaToSwaggerConverter.remove_comments(form_schema)

      unless Flipper.enabled?(:decision_review_sc_pact_act_boolean)
        response.tap do |s|
          s.dig(*%w[definitions scCreate properties data properties attributes properties])&.delete('potentialPactAct')
        end
      end

      render json: response
    end

    def show
      sc = AppealsApi::SupplementalClaim.select(ALLOWED_COLUMNS).find(params[:id])
      sc = with_status_simulation(sc) if status_requested_and_allowed?

      render_supplemental_claim(sc)
    rescue ActiveRecord::RecordNotFound
      render_supplemental_claim_not_found(params[:id])
    end

    def validate
      render json: {
        data: {
          type: 'supplementalClaimValidation',
          attributes: {
            status: 'valid'
          }
        }
      }
    end

    def create
      sc = AppealsApi::SupplementalClaim.new(
        auth_headers: request_headers,
        form_data: @json_body,
        source: request_headers['X-Consumer-Username'].presence&.strip,
        evidence_submission_indicated: evidence_submission_indicated?,
        api_version: self.class::API_VERSION,
        veteran_icn: @json_body.dig('data', 'attributes', 'veteran', 'icn')
      )

      return render_model_errors(sc) unless sc.validate

      sc.save
      AppealsApi::PdfSubmitJob.perform_async(sc.id, 'AppealsApi::SupplementalClaim', 'v3')
      render_supplemental_claim(sc, status: :created)
    end

    def download
      id = params[:id]
      supplemental_claim = AppealsApi::SupplementalClaim.find(id)

      render_appeal_pdf_download(supplemental_claim, "#{FORM_NUMBER}-supplemental-claim-#{id}.pdf", params[:icn])
    rescue ActiveRecord::RecordNotFound
      render_supplemental_claim_not_found(id)
    end

    private

    def evidence_submission_indicated?
      @json_body.dig('data', 'attributes', 'evidenceSubmission', 'evidenceType').include?('upload')
    end

    def validate_icn_parameter
      detail = nil

      if params[:icn].blank?
        detail = "'icn' parameter is required"
      elsif !ICN_REGEX.match?(params[:icn])
        detail = "'icn' parameter has an invalid format. Pattern: #{ICN_REGEX.inspect}"
      end

      raise Common::Exceptions::UnprocessableEntity.new(detail:) if detail.present?
    end

    def validate_json_schema
      validate_headers(request_headers)
      validate_form_data(@json_body)
    rescue Common::Exceptions::DetailedSchemaErrors => e
      render json: { errors: e.errors }, status: :unprocessable_entity
    end

    def render_supplemental_claim(sc, **)
      render(json: SupplementalClaimSerializer.new(sc).serializable_hash, **)
    end

    def render_supplemental_claim_not_found(id)
      raise Common::Exceptions::ResourceNotFound.new(
        detail: I18n.t('appeals_api.errors.not_found', type: 'Supplemental Claim', id:)
      )
    end

    def header_names = headers_schema['definitions']['scCreateParameters']['properties'].keys

    def request_headers
      header_names.index_with { |key| request.headers[key] }.compact
    end

    def render_model_errors(model)
      render json: model_errors_to_json_api(model), status: MODEL_ERROR_STATUS
    end

    def token_validation_api_key
      Settings.dig(:modules_appeals_api, :token_validation, :supplemental_claims, :api_key)
    end
  end
end
