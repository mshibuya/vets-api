# frozen_string_literal: true

module ClaimsApi
  module V2
    class DisabilityCompensationEvssMapper
      def initialize(auto_claim, file_number)
        @auto_claim = auto_claim
        @data = auto_claim&.form_data&.deep_symbolize_keys
        @evss_claim = {}
        @file_number = file_number
      end

      def map_claim
        claim_attributes
        claim_meta

        # must set to true by default so the EVSS Docker Container
        # does not submit a duplicate PDF
        @evss_claim[:autoCestPDFGenerationDisabled] = true
        { form526: @evss_claim }
      end

      private

      def claim_attributes
        service_information
        current_mailing_address
        disabilities
        standard_claim
        claim_process_type
        veteran_meta
      end

      def service_information
        info = @data[:serviceInformation]
        service_periods = format_service_periods(info&.dig(:servicePeriods))

        @evss_claim[:serviceInformation] = {
          servicePeriods: service_periods
        }
      end

      def current_mailing_address
        addr = @data.dig(:veteranIdentification, :mailingAddress) || {}
        @evss_claim[:veteran] ||= {}
        @evss_claim[:veteran][:currentMailingAddress] = addr
        @evss_claim[:veteran][:currentMailingAddress].merge!({ type: 'DOMESTIC' })
        @evss_claim[:veteran][:currentMailingAddress].except!(:numberAndStreet, :apartmentOrUnitNumber)
        if @evss_claim[:veteran][:currentMailingAddress][:zipLastFour].blank?
          @evss_claim[:veteran][:currentMailingAddress].except!(:zipLastFour)
        end
      end

      def disabilities
        @evss_claim[:disabilities] = @data[:disabilities]&.map { |disability| transform_disability_values!(disability) }
      end

      def transform_disability_values!(disability)
        if disability&.dig(:secondaryDisabilities).present?
          disability[:secondaryDisabilities] = disability[:secondaryDisabilities]&.map do |secondary|
            secondary.except(:exposureOrEventOrInjury, :approximateDate)
          end
        end
        check_for_pact_special_issue(disability)

        disability.except(:approximateDate, :isRelatedToToxicExposure)
      end

      def check_for_pact_special_issue(disability)
        related_to_toxic_exposure = disability[:isRelatedToToxicExposure]
        disability[:specialIssues] = ['PACT'] if related_to_toxic_exposure
      end

      def standard_claim
        @evss_claim[:standardClaim] = @data[:claimProcessType] == 'STANDARD_CLAIM_PROCESS'
      end

      def claim_process_type
        @evss_claim[:claimProcessType] = 'BDD_PROGRAM_CLAIM' if @data[:claimProcessType] == 'BDD_PROGRAM'
      end

      def claim_meta
        @evss_claim[:applicationExpirationDate] = Time.zone.today + 1.year
        @evss_claim[:claimantCertification] = @data[:claimantCertification]
        @evss_claim[:submtrApplcnTypeCd] = 'LH-B'
      end

      def veteran_meta
        @evss_claim[:veteran] ||= {}
        # EVSS Docker needs currentlyVAEmployee, 526 schema uses currentVaEmployee
        @evss_claim[:veteran][:currentlyVAEmployee] = @data.dig(:veteranIdentification, :currentVaEmployee)
        email_address = @data.dig(:veteranIdentification, :emailAddress, :email)
        @evss_claim[:veteran][:emailAddress] = email_address unless email_address.nil?
        @evss_claim[:veteran][:fileNumber] = @file_number
      end

      # Convert 12-05-1984 to 1984-12-05 for Docker container
      def format_service_periods(service_period_dates)
        service_period_dates.each do |sp_date|
          next if sp_date[:activeDutyBeginDate].nil?

          begin_year = Date.strptime(sp_date[:activeDutyBeginDate], '%Y-%m-%d')
          sp_date[:activeDutyBeginDate] = begin_year.strftime('%Y-%m-%d')
          next if sp_date[:activeDutyEndDate].nil?

          end_year = Date.strptime(sp_date[:activeDutyEndDate], '%Y-%m-%d')
          sp_date[:activeDutyEndDate] = end_year.strftime('%Y-%m-%d')
        end
      end
    end
  end
end
