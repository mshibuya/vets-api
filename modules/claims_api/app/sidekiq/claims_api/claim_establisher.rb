# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/monitored_worker'
require 'evss/disability_compensation_form/service_exception'
require 'evss/disability_compensation_form/service'
require 'evss_service/base' # docker container
require 'sentry_logging'
require 'claims_api/claim_logger'

module ClaimsApi
  class ClaimEstablisher
    include Sidekiq::Job
    include SentryLogging
    include Sidekiq::MonitoredWorker

    def perform(auto_claim_id) # rubocop:disable Metrics/MethodLength
      auto_claim = ClaimsApi::AutoEstablishedClaim.find(auto_claim_id)

      orig_form_data = auto_claim.form_data
      form_data = auto_claim.to_internal
      auth_headers = auto_claim.auth_headers

      if Flipper.enabled? :claims_status_v1_lh_auto_establish_claim_enabled
        begin
          response = service(auth_headers).submit(auto_claim, form_data)
        # Temporary errors (returning HTML, connection timeout), retry call
        rescue Faraday::ParsingError, Faraday::TimeoutError => e
          ClaimsApi::Logger.log('claims_establisher',
                                retry: true,
                                detail: "/submit failure for claimId #{auto_claim&.id}: #{e.message}, #{e.class}")
          raise e
        end

        ClaimsApi::Logger.log('526_docker_container', claim_id: auto_claim_id,
                                                      vbms_id: response[:claimId])

        auto_claim.evss_id = response[:claimId]
      else
        response = service(auth_headers).submit_form526(form_data)
        ClaimsApi::Logger.log('526', claim_id: auto_claim_id,
                                     vbms_id: response.claim_id)

        auto_claim.evss_id = response.claim_id
      end

      auto_claim.status = ClaimsApi::AutoEstablishedClaim::ESTABLISHED
      auto_claim.evss_response = nil
      auto_claim.save!

      queue_flash_updater(auto_claim.flashes, auto_claim_id)
      queue_special_issues_updater(auto_claim.special_issues, auto_claim)
    rescue ::EVSS::DisabilityCompensationForm::ServiceException => e
      auto_claim.status = ClaimsApi::AutoEstablishedClaim::ERRORED
      auto_claim.evss_response = e.messages
      auto_claim.form_data = orig_form_data
      auto_claim.save
      log_exception_to_sentry(e)
    rescue ::Common::Exceptions::BackendServiceException => e
      ClaimsApi::Logger.log('claims_establisher',
                            retry: false,
                            detail: "/submit failure for claimId #{auto_claim&.id}: #{e.original_body}, #{e.class}")
      auto_claim.status = ClaimsApi::AutoEstablishedClaim::ERRORED
      auto_claim.evss_response = [{ 'key' => e.status_code, 'severity' => 'FATAL', 'text' => e.original_body }]
      auto_claim.form_data = orig_form_data
      auto_claim.save
      log_exception_to_sentry(e)
    rescue => e
      auto_claim.status = ClaimsApi::AutoEstablishedClaim::ERRORED
      auto_claim.evss_response = e.detailed_message
      auto_claim.form_data = orig_form_data
      auto_claim.save
      log_exception_to_sentry(e)
      raise e
    end

    private

    def veteran_from_headers(auth_headers)
      vet = ClaimsApi::Veteran.new(
        uuid: JSON.parse(auth_headers['va_eauth_authorization'])['authorizationResponse']['id'],
        ssn: JSON.parse(auth_headers['va_eauth_authorization'])['authorizationResponse']['id'],
        first_name: auth_headers['va_eauth_firstName'],
        last_name: auth_headers['va_eauth_lastName'],
        va_profile: ClaimsApi::Veteran.build_profile(auth_headers['va_eauth_birthdate'])
      )
      vet.mpi_record?
      vet.edipi = vet.edipi_mpi
      vet.participant_id = vet.participant_id_mpi

      vet
    rescue NoMethodError
      nil
    end

    def queue_special_issues_updater(special_issues_per_disability, auto_claim)
      return if special_issues_per_disability.blank?

      special_issues_per_disability.each do |disability|
        contention_id = {
          claim_id: auto_claim.evss_id,
          code: disability['code'],
          name: disability['name']
        }
        ClaimsApi::SpecialIssueUpdater.perform_async(contention_id,
                                                     disability['special_issues'],
                                                     auto_claim.id)
      end
    end

    def queue_flash_updater(flashes, auto_claim_id)
      return if flashes.blank?

      ClaimsApi::FlashUpdater.perform_async(flashes, auto_claim_id)
    end

    def service(auth_headers)
      if Flipper.enabled? :claims_status_v1_lh_auto_establish_claim_enabled
        ClaimsApi::EVSSService::Base.new
      elsif Settings.claims_api.disability_claims_mock_override && !auth_headers['Mock-Override']
        ClaimsApi::DisabilityCompensation::MockOverrideService.new(auth_headers)
      else
        EVSS::DisabilityCompensationForm::Service.new(auth_headers)
      end
    end
  end
end
