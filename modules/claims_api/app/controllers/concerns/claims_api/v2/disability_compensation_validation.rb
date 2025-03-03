# frozen_string_literal: false

require 'claims_api/v2/disability_compensation_shared_service_module'

module ClaimsApi
  module V2
    module DisabilityCompensationValidation # rubocop:disable Metrics/ModuleLength
      include DisabilityCompensationSharedServiceModule
      DATE_FORMATS = {
        10 => 'yyyy-mm-dd',
        7 => 'yyyy-mm',
        4 => 'yyyy'
      }.freeze
      BDD_LOWER_LIMIT = 90
      BDD_UPPER_LIMIT = 180

      CLAIM_DATE = Time.find_zone!('Central Time (US & Canada)').today.freeze
      YYYY_YYYYMM_REGEX = '^(?:19|20)[0-9][0-9]$|^(?:19|20)[0-9][0-9]-(0[1-9]|1[0-2])$'.freeze

      def validate_form_526_submission_values!(target_veteran)
        validate_claim_process_type_bdd! if bdd_claim?
        # ensure 'claimantCertification' is true
        validate_form_526_claimant_certification!
        # ensure mailing address country is valid
        validate_form_526_identification!
        # ensure disabilities are valid
        validate_form_526_disabilities!
        # ensure homeless information is valid
        validate_form_526_veteran_homelessness!
        # ensure toxic exposure info is valid
        validate_form_526_gulf_service!
        # ensure new address is valid
        validate_form_526_change_of_address!
        # ensure military service pay information is valid
        validate_form_526_service_pay!
        # ensure treament centers information is valid
        validate_form_526_treatments!
        # ensure service information is valid
        validate_form_526_service_information!(target_veteran)
        # ensure direct deposit information is valid
        validate_form_526_direct_deposit!
      end

      def validate_form_526_change_of_address!
        return if form_attributes['changeOfAddress'].blank?

        validate_form_526_change_of_address_required_fields!
        validate_form_526_change_of_address_beginning_date!
        validate_form_526_change_of_address_ending_date!
        validate_form_526_change_of_address_country!
      end

      def validate_form_526_change_of_address_required_fields!
        change_of_address = form_attributes['changeOfAddress']
        coa_begin_date = change_of_address&.dig('dates', 'beginDate') # we can have a valid form without an endDate

        form_object_desc = 'change of address'

        raise_exception_if_value_not_present('begin date', form_object_desc) if coa_begin_date.blank?
      end

      def validate_form_526_change_of_address_beginning_date!
        change_of_address = form_attributes['changeOfAddress']
        date = change_of_address.dig('dates', 'beginDate')

        # If the date parse fails, then fall back to the InvalidFieldValue
        begin
          nil if Date.strptime(date, '%Y-%m-%d') < Time.zone.now
        rescue
          raise ::Common::Exceptions::InvalidFieldValue.new('changeOfAddress.dates.beginDate', date)
        end
      end

      def validate_form_526_change_of_address_ending_date!
        change_of_address = form_attributes['changeOfAddress']
        date = change_of_address.dig('dates', 'endDate')
        if 'PERMANENT'.casecmp?(change_of_address['typeOfAddressChange']) && date.present?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: '"changeOfAddress.dates.endDate" cannot be included when typeOfAddressChange is PERMANENT'
          )
        end
        return unless 'TEMPORARY'.casecmp?(change_of_address['typeOfAddressChange'])

        form_object_desc = 'a TEMPORARY change of address'

        raise_exception_if_value_not_present('end date', form_object_desc) if date.blank?

        return if Date.strptime(date,
                                '%Y-%m-%d') > Date.strptime(change_of_address.dig('dates', 'beginDate'), '%Y-%m-%d')

        raise ::Common::Exceptions::InvalidFieldValue.new('changeOfAddress.dates.endDate', date)
      end

      def validate_form_526_change_of_address_country!
        country = form_attributes.dig('changeOfAddress', 'country')
        return if country.nil? || valid_countries.include?(country)

        raise ::Common::Exceptions::InvalidFieldValue.new('changeOfAddress.country', country)
      end

      def validate_form_526_claimant_certification!
        return unless form_attributes['claimantCertification'] == false

        raise ::Common::Exceptions::InvalidFieldValue.new('claimantCertification',
                                                          form_attributes['claimantCertification'])
      end

      def validate_form_526_identification!
        validate_form_526_current_mailing_address_country!
        validate_form_526_service_number!
      end

      def validate_form_526_service_number!
        service_num = form_attributes.dig('veteranIdentification', 'serviceNumber')
        return if service_num.nil?
        if service_num.length > 9
          raise ::Common::Exceptions::UnprocessableEntity.new(detail: "serviceNumber, #{service_num} is too long")
        end
      end

      def validate_form_526_current_mailing_address_country!
        mailing_address = form_attributes.dig('veteranIdentification', 'mailingAddress')
        return if valid_countries.include?(mailing_address['country'])

        raise ::Common::Exceptions::InvalidFieldValue.new('country', mailing_address['country'])
      end

      def validate_form_526_disabilities!
        validate_form_526_disability_classification_code!
        validate_form_526_disability_approximate_begin_date!
        validate_form_526_disability_service_relevance!
        validate_form_526_disability_secondary_disabilities!
      end

      def validate_form_526_disability_classification_code!
        return if (form_attributes['disabilities'].pluck('classificationCode') - [nil]).blank?

        form_attributes['disabilities'].each do |disability|
          next if disability['classificationCode'].blank?

          if brd_classification_ids.include?(disability['classificationCode'].to_i)
            validate_form_526_disability_code_enddate!(disability['classificationCode'].to_i)
          else
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "'disabilities.classificationCode' must match an active code " \
                      'returned from the /disabilities endpoint of the Benefits ' \
                      'Reference Data API.'
            )
          end
        end
      end

      def validate_form_526_disability_code_enddate!(classification_code)
        reference_disability = brd_disabilities.find { |x| x[:id] == classification_code }
        end_date_time = reference_disability[:endDateTime]
        return if end_date_time.nil?

        if Date.parse(end_date_time) < Time.zone.today
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "'disabilities.classificationCode' is no longer active."
          )
        end
      end

      def validate_form_526_disability_approximate_begin_date!
        disabilities = form_attributes['disabilities']
        return if disabilities.blank?

        disabilities.each_with_index do |disability, idx|
          approx_begin_date = disability['approximateDate']
          next if approx_begin_date.blank?

          date_is_valid?(approx_begin_date, "disability/#{idx}/approximateDate")

          next if date_is_valid_against_current_time_after_check_on_format?(approx_begin_date)

          raise ::Common::Exceptions::InvalidFieldValue.new('disability.approximateDate', approx_begin_date)
        end
      end

      def validate_form_526_disability_service_relevance!
        disabilities = form_attributes['disabilities']
        return if disabilities.blank?

        disabilities.each do |disability|
          disability_action_type = disability&.dig('disabilityActionType')
          service_relevance = disability&.dig('serviceRelevance')
          if disability_action_type == 'NEW' && service_relevance.blank?
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "'disabilities.serviceRelevance' is required if 'disabilities.disabilityActionType' is NEW."
            )
          end
        end
      end

      def validate_form_526_disability_secondary_disabilities!
        form_attributes['disabilities'].each do |disability|
          next if disability['secondaryDisabilities'].blank?

          validate_form_526_disability_secondary_disability_required_fields!(disability)

          disability['secondaryDisabilities'].each do |secondary_disability|
            if secondary_disability['classificationCode'].present?
              validate_form_526_disability_secondary_disability_classification_code!(secondary_disability)
              validate_form_526_disability_code_enddate!(secondary_disability['classificationCode'].to_i)
            end

            if secondary_disability['approximateDate'].present?
              validate_form_526_disability_secondary_disability_approximate_begin_date!(secondary_disability)
            end
          end
        end
      end

      def validate_form_526_disability_secondary_disability_required_fields!(disability)
        disability['secondaryDisabilities'].each do |secondary_disability|
          sd_name = secondary_disability&.dig('name')
          sd_disability_action_type = secondary_disability&.dig('disabilityActionType')
          sd_service_relevance = secondary_disability&.dig('serviceRelevance')

          form_object_desc = 'secondary disability'

          raise_exception_if_value_not_present('name', form_object_desc) if sd_name.blank?
          if sd_disability_action_type.blank?
            raise_exception_if_value_not_present('disability action type',
                                                 form_object_desc)
          end
          if sd_service_relevance.blank?
            raise_exception_if_value_not_present('service relevance',
                                                 form_object_desc)
          end
        end
      end

      def validate_form_526_disability_secondary_disability_classification_code!(secondary_disability)
        return if brd_classification_ids.include?(secondary_disability['classificationCode'].to_i)

        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "'disabilities.secondaryDisabilities.classificationCode' must match an active code " \
                  'returned from the /disabilities endpoint of the Benefits Reference Data API.'
        )
      end

      def validate_form_526_disability_secondary_disability_approximate_begin_date!(secondary_disability)
        date_is_valid?(secondary_disability['approximateDate'], 'disabilities.secondaryDisabilities.approximateDate')

        return if date_is_valid_against_current_time_after_check_on_format?(secondary_disability['approximateDate'])

        raise ::Common::Exceptions::InvalidFieldValue.new(
          'disabilities.secondaryDisabilities.approximateDate',
          secondary_disability['approximateDate']
        )
      rescue ArgumentError
        raise ::Common::Exceptions::InvalidFieldValue.new(
          'disabilities.secondaryDisabilities.approximateDate',
          secondary_disability['approximateDate']
        )
      end

      def validate_form_526_veteran_homelessness! # rubocop:disable Metrics/MethodLength
        handle_empty_other_description

        if too_many_homelessness_attributes_provided?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "Must define only one of 'homeless.currentlyHomeless' or " \
                    "'homeless.riskOfBecomingHomeless'"
          )
        end

        if unnecessary_homelessness_point_of_contact_provided?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "If 'homeless.pointOfContact' is defined, then one of " \
                    "'homeless.currentlyHomeless' or 'homeless.riskOfBecomingHomeless' is required"
          )
        end

        if missing_point_of_contact?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "If one of 'homeless.currentlyHomeless' or 'homeless.riskOfBecomingHomeless' is " \
                    "defined, then 'homeless.pointOfContact' is required"
          )
        end

        if international_phone_too_long?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'International telephone number must be shorter than 25 characters'
          )
        end
      end

      def get_homelessness_attributes
        currently_homeless_attr = form_attributes.dig('homeless', 'currentlyHomeless')
        homelessness_risk_attr = form_attributes.dig('homeless', 'riskOfBecomingHomeless')
        [currently_homeless_attr, homelessness_risk_attr]
      end

      def handle_empty_other_description
        currently_homeless_attr, homelessness_risk_attr = get_homelessness_attributes

        # Set otherDescription to ' ' to bypass docker container validation
        if currently_homeless_attr.present?
          homeless_situation_options = currently_homeless_attr['homelessSituationOptions']
          other_description = currently_homeless_attr['otherDescription']
          if homeless_situation_options == 'OTHER' && other_description.blank?
            form_attributes['homeless']['currentlyHomeless']['otherDescription'] = ' '
          end
        elsif homelessness_risk_attr.present?
          living_situation_options = homelessness_risk_attr['livingSituationOptions']
          other_description = homelessness_risk_attr['otherDescription']
          if living_situation_options == 'other' && other_description.blank?
            form_attributes['homeless']['riskOfBecomingHomeless']['otherDescription'] = ' '
          end
        end
      end

      def too_many_homelessness_attributes_provided?
        currently_homeless_attr, homelessness_risk_attr = get_homelessness_attributes
        # EVSS does not allow both attributes to be provided at the same time
        currently_homeless_attr.present? && homelessness_risk_attr.present?
      end

      def unnecessary_homelessness_point_of_contact_provided?
        currently_homeless_attr, homelessness_risk_attr = get_homelessness_attributes
        homelessness_poc_attr = form_attributes.dig('homeless', 'pointOfContact')

        # EVSS does not allow passing a 'pointOfContact' if neither homelessness attribute is provided
        currently_homeless_attr.blank? && homelessness_risk_attr.blank? && homelessness_poc_attr.present?
      end

      def missing_point_of_contact?
        homelessness_poc_attr = form_attributes.dig('homeless', 'pointOfContact')
        currently_homeless_attr, homelessness_risk_attr = get_homelessness_attributes

        # 'pointOfContact' is required when either currentlyHomeless or homelessnessRisk is provided
        homelessness_poc_attr.blank? && (currently_homeless_attr.present? || homelessness_risk_attr.present?)
      end

      def international_phone_too_long?
        phone = form_attributes.dig('homeless', 'pointOfContactNumber', 'internationalTelephone')
        phone.length > 25 if phone
      end

      def validate_form_526_gulf_service!
        gulf_war_service = form_attributes&.dig('toxicExposure', 'gulfWarHazardService')
        return if gulf_war_service&.dig('servedInGulfWarHazardLocations') == 'NO'

        begin_date = gulf_war_service&.dig('serviceDates', 'beginDate')
        end_date = gulf_war_service&.dig('serviceDates', 'endDate')

        begin_property = 'toxicExposure/gulfWarHazardService/serviceDates/beginDate'
        end_property = 'toxicExposure/gulfWarHazardService/serviceDates/endDate'

        validate_gulf_war_service_date(begin_date) unless begin_date.nil? || !date_is_valid?(begin_date,
                                                                                             begin_property)
        validate_gulf_war_service_date(end_date) unless end_date.nil? || !date_is_valid?(end_date,
                                                                                         end_property)
      end

      def validate_gulf_war_service_date(date)
        if date_has_day?(date) # this date should not have the day
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'Service dates must be in the format of yyyy-mm or yyyy'
          )
        end
      end

      def validate_form_526_service_pay!
        validate_form_526_military_retired_pay!
        validate_form_526_future_military_retired_pay!
        validate_from_526_military_retired_pay_branch!
        validate_form_526_separation_pay_received_date!
        validate_from_526_separation_severance_pay_branch!
      end

      def validate_form_526_military_retired_pay!
        receiving_attr = form_attributes.dig('servicePay', 'receivingMilitaryRetiredPay')
        future_attr = form_attributes.dig('servicePay', 'futureMilitaryRetiredPay')

        return if receiving_attr.nil?
        return unless receiving_attr == future_attr

        # EVSS does not allow both attributes to be the same value (unless that value is nil)
        raise ::Common::Exceptions::InvalidFieldValue.new(
          "'servicePay.receivingMilitaryRetiredPay' and 'servicePay.futureMilitaryRetiredPay '" \
          'should not be the same value', receiving_attr
        )
      end

      def validate_from_526_military_retired_pay_branch!
        return if form_attributes.dig('servicePay', 'militaryRetiredPay').nil?

        branch = form_attributes.dig('servicePay', 'militaryRetiredPay', 'branchOfService')
        return if branch.nil? || brd_service_branch_names.include?(branch)

        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "'servicePay.militaryRetiredPay.branchOfService' must match a service branch " \
                  'returned from the /service-branches endpoint of the Benefits ' \
                  'Reference Data API.'
        )
      end

      def validate_form_526_future_military_retired_pay!
        future_attr = form_attributes.dig('servicePay', 'futureMilitaryRetiredPay')
        future_explanation_attr = form_attributes.dig('servicePay', 'futureMilitaryRetiredPayExplanation')
        return if future_attr.nil?

        if future_attr == 'YES' && future_explanation_attr.blank?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "If 'servicePay.futureMilitaryRetiredPay' is true, then " \
                    "'servicePay.futureMilitaryRetiredPayExplanation' is required"
          )
        end
      end

      def validate_form_526_separation_pay_received_date!
        separation_pay_received_date = form_attributes.dig('servicePay', 'separationSeverancePay',
                                                           'datePaymentReceived')
        return if separation_pay_received_date.blank?

        return if date_is_valid_against_current_time_after_check_on_format?(separation_pay_received_date)

        raise ::Common::Exceptions::InvalidFieldValue.new('separationSeverancePay.datePaymentReceived',
                                                          separation_pay_received_date)
      end

      def validate_from_526_separation_severance_pay_branch!
        branch = form_attributes.dig('servicePay', 'separationSeverancePay', 'branchOfService')
        return if branch.nil? || brd_service_branch_names.include?(branch)

        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "'servicePay.separationSeverancePay.branchOfService' must match a service branch " \
                  'returned from the /service-branches endpoint of the Benefits ' \
                  'Reference Data API.'
        )
      end

      def validate_form_526_treatments!
        treatments = form_attributes['treatments']
        return if treatments.blank?

        validate_treated_disability_names!(treatments)
        validate_treatment_dates(treatments)
      end

      def validate_treated_disability_names!(treatments)
        treated_disability_names = collect_treated_disability_names(treatments)
        declared_disability_names = collect_primary_secondary_disability_names(form_attributes['disabilities'])

        treated_disability_names.each do |treatment|
          next if declared_disability_names.include?(treatment)

          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'The treated disability must match a disability listed above'
          )
        end
      end

      def collect_treated_disability_names(treatments)
        names = []
        treatments.each do |treatment|
          treatment['treatedDisabilityNames']&.each do |disability_name|
            names << disability_name.strip.downcase
          end
        end
        names
      end

      def validate_treatment_dates(treatments) # rubocop:disable Metrics/MethodLength
        first_service_period = form_attributes['serviceInformation']['servicePeriods'].min_by do |per|
          per['activeDutyBeginDate']
        end
        if first_service_period['activeDutyBeginDate']
          return unless date_is_valid?(first_service_period['activeDutyBeginDate'], 'servicePeriod.activeDutyBeginDate')

          first_service_date = Date.strptime(first_service_period['activeDutyBeginDate'],
                                             '%Y-%m-%d')
        end
        treatments.each do |treatment|
          next if treatment['beginDate'].nil?

          treatment_begin_date = if type_of_date_format(treatment['beginDate']) == 'yyyy-mm'
                                   Date.strptime(treatment['beginDate'], '%Y-%m')
                                 elsif type_of_date_format(treatment['beginDate']) == 'yyyy'
                                   Date.strptime(treatment['beginDate'], '%Y')

                                 else
                                   raise ::Common::Exceptions::UnprocessableEntity.new(
                                     detail: 'Each treatment begin date must be in the format of yyyy-mm or yyyy.'
                                   )
                                 end
          next if first_service_date.blank? || treatment_begin_date >= first_service_date

          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "Each treatment begin date must be after the first 'servicePeriod.activeDutyBeginDate'."
          )
        end
      end

      def collect_primary_secondary_disability_names(disabilities)
        names = []
        disabilities.each do |disability|
          names << disability['name'].strip.downcase
          disability['secondaryDisabilities']&.each do |secondary|
            names << secondary['name'].strip.downcase
          end
        end
        names
      end

      def validate_form_526_service_information!(target_veteran)
        service_information = form_attributes['serviceInformation']

        if service_information.blank?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'Service information is required'
          )
        end
        validate_claim_date_to_active_duty_end_date!(service_information)
        validate_service_periods!(service_information, target_veteran)
        validate_service_branch_names!(service_information)
        validate_confinements!(service_information)
        validate_alternate_names!(service_information)
        validate_reserves_required_values!(service_information)
        validate_form_526_location_codes!(service_information)
      end

      def validate_claim_date_to_active_duty_end_date!(service_information)
        ant_sep_date = form_attributes&.dig('serviceInformation', 'federalActivation', 'anticipatedSeparationDate')
        unless service_information['servicePeriods'].nil?
          max_period = service_information['servicePeriods'].max_by { |sp| sp['activeDutyEndDate'] }
        end
        max_active_duty_end_date = max_period['activeDutyEndDate']

        return unless date_is_valid?(max_active_duty_end_date, 'servicePeriod.activeDutyBeginDate')

        if ant_sep_date.present? && max_active_duty_end_date.present? &&
           ((Date.strptime(max_period['activeDutyEndDate'], '%Y-%m-%d') > Date.strptime(CLAIM_DATE.to_s, '%Y-%m-%d') +
           180.days) || (Date.strptime(ant_sep_date,
                                       '%Y-%m-%d') > Date.strptime(CLAIM_DATE.to_s, '%Y-%m-%d') + 180.days))

          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'Service members cannot submit a claim until they are within 180 days of their separation date.'
          )
        end
      end

      def validate_service_periods!(service_information, target_veteran)
        date_of_birth = Date.strptime(target_veteran.birth_date, '%Y%m%d')
        age_thirteen = date_of_birth.next_year(13)
        service_information['servicePeriods'].each do |sp|
          if sp['activeDutyBeginDate']
            next unless date_is_valid?(sp['activeDutyBeginDate'], 'servicePeriod.activeDutyBeginDate')

            age_exception if Date.strptime(sp['activeDutyBeginDate'], '%Y-%m-%d') <= age_thirteen

            if sp['activeDutyEndDate']
              next unless date_is_valid?(sp['activeDutyEndDate'], 'servicePeriod.activeDutyBeginDate')

              if Date.strptime(sp['activeDutyBeginDate'], '%Y-%m-%d') > Date.strptime(
                sp['activeDutyEndDate'], '%Y-%m-%d'
              )
                begin_date_exception
              end
            end
          end

          if sp['activeDutyEndDate'] && Date.strptime(sp['activeDutyEndDate'],
                                                      '%Y-%m-%d') > Time.zone.now && sp['separationLocationCode'].blank?
            location_code_exception
          end
        end
      end

      def age_exception
        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "Active Duty Begin Date cannot be on or before Veteran's thirteenth birthday."
        )
      end

      def begin_date_exception
        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: 'Active Duty End Date needs to be after Active Duty Start Date'
        )
      end

      def location_code_exception
        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: 'If Active Duty End Date is in the future a Separation Location Code is required.'
        )
      end

      def validate_form_526_location_codes!(service_information)
        # only retrieve separation locations if we'll need them
        need_locations = service_information['servicePeriods'].detect do |service_period|
          if service_period['activeDutyEndDate']
            Date.strptime(service_period['activeDutyEndDate'],
                          '%Y-%m-%d') > Time.zone.today
          end
        end
        separation_locations = retrieve_separation_locations if need_locations

        service_information['servicePeriods'].each do |service_period|
          next if service_period['activeDutyEndDate'] && Date.strptime(service_period['activeDutyEndDate'],
                                                                       '%Y-%m-%d') <= Time.zone.today
          next if separation_locations&.any? do |location|
                    if service_period['separationLocationCode']
                      @location_code = service_period['separationLocationCode']
                      location[:id].to_s == @location_code
                    end
                  end
        end
      end

      def validate_confinements!(service_information) # rubocop:disable Metrics/MethodLength
        confinements = service_information&.dig('confinements')

        return if confinements.blank?

        confinements.each do |confinement|
          approximate_begin_date = confinement&.dig('approximateBeginDate')
          approximate_end_date = confinement&.dig('approximateEndDate')

          form_object_desc = 'a confinement period'
          if approximate_begin_date.blank?
            raise_exception_if_value_not_present('approximate begin date',
                                                 form_object_desc)
          end
          if approximate_end_date.blank?
            raise_exception_if_value_not_present('approximate end date',
                                                 form_object_desc)
          end

          if begin_date_is_after_end_date?(approximate_begin_date, approximate_end_date)
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: 'Confinement approximate end date must be after approximate begin date.'
            )
          end

          service_periods = service_information&.dig('servicePeriods')
          earliest_active_duty_begin_date = find_earliest_active_duty_begin_date(service_periods)

          next if earliest_active_duty_begin_date['activeDutyBeginDate'].blank? # nothing to check against below

          # if confinementBeginDate is before earliest activeDutyBeginDate, raise error
          if duty_begin_date_is_after_approximate_begin_date?(earliest_active_duty_begin_date['activeDutyBeginDate'],
                                                              approximate_begin_date)
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: 'Confinement approximate begin date must be after earliest active duty begin date.'
            )
          end
        end
      end

      def validate_alternate_names!(service_information)
        alternate_names = service_information&.dig('alternateNames')
        return if alternate_names.blank?

        # clean them up to compare
        alternate_names = alternate_names.map(&:strip).map(&:downcase)

        # returns nil unless there are duplicate names
        duplicate_names_check = alternate_names.detect { |e| alternate_names.rindex(e) != alternate_names.index(e) }

        unless duplicate_names_check.nil?
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'Names entered as an alternate name must be unique.'
          )
        end
      end

      def validate_service_branch_names!(service_information)
        downcase_branches = brd_service_branch_names.map(&:downcase)
        service_information['servicePeriods'].each do |sp|
          unless downcase_branches.include?(sp['serviceBranch'].downcase)
            raise ::Common::Exceptions::UnprocessableEntity.new(
              detail: "'servicePeriods.serviceBranch' must match a service branch " \
                      'returned from the /service-branches endpoint of the Benefits ' \
                      'Reference Data API.'
            )
          end
        end
      end

      def validate_reserves_required_values!(service_information)
        validate_federal_activation_values!(service_information)
        reserves = service_information&.dig('reservesNationalGuardService')

        return if reserves.blank?

        # if reserves is not empty the we require tos dates
        validate_reserves_tos_dates!(reserves)
      end

      def validate_reserves_tos_dates!(reserves)
        tos = reserves&.dig('obligationTermsOfService')
        return if tos.blank?

        tos_start_date = tos&.dig('beginDate')
        tos_end_date = tos&.dig('endDate')

        form_obj_desc = 'obligation terms of service'

        # if one is present both need to be present
        raise_exception_if_value_not_present('begin date', form_obj_desc) if tos_start_date.blank?
        raise_exception_if_value_not_present('end date', form_obj_desc) if tos_end_date.blank?

        if Date.strptime(tos_start_date, '%Y-%m-%d') > Date.strptime(tos_end_date, '%Y-%m-%d')
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'Terms of service begin date must be before the terms of service end date.'
          )
        end
      end

      def validate_federal_activation_values!(service_information)
        federal_activation = service_information&.dig('federalActivation')
        federal_activation_date = federal_activation&.dig('activationDate')
        anticipated_seperation_date = federal_activation&.dig('anticipatedSeparationDate')

        return if federal_activation.blank?

        form_obj_desc = 'federal activation'

        if federal_activation_date.blank?
          raise_exception_if_value_not_present('federal activation date',
                                               form_obj_desc)
        end

        return if anticipated_seperation_date.blank?

        # we know the dates are present
        if activation_date_not_after_duty_begin_date?(federal_activation_date)
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'The federal activation date must be after the earliest service period active duty begin date.'
          )
        end

        validate_anticipated_seperation_date_in_past!(anticipated_seperation_date)
      end

      def activation_date_not_after_duty_begin_date?(activation_date)
        service_information = form_attributes['serviceInformation']
        service_periods = service_information&.dig('servicePeriods')

        earliest_active_duty_begin_date = find_earliest_active_duty_begin_date(service_periods)

        # return true if activationDate is an earlier date
        return false if earliest_active_duty_begin_date['activeDutyBeginDate'].nil?

        Date.parse(activation_date) < Date.strptime(earliest_active_duty_begin_date['activeDutyBeginDate'],
                                                    '%Y-%m-%d')
      end

      def find_earliest_active_duty_begin_date(service_periods)
        service_periods.min_by do |a|
          next unless date_is_valid?(a['activeDutyBeginDate'], 'servicePeriod.activeDutyBeginDate')

          Date.strptime(a['activeDutyBeginDate'], '%Y-%m-%d') if a['activeDutyBeginDate']
        end
      end

      def validate_anticipated_seperation_date_in_past!(date)
        if Date.strptime(date, '%Y-%m-%d') < Time.zone.now
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: 'The anticipated separation date must be a date in the future.'
          )
        end
      end

      def validate_form_526_direct_deposit!
        direct_deposit = form_attributes['directDeposit']
        return if direct_deposit.blank?

        account_check = direct_deposit&.dig('noAccount')

        account_check.present? && account_check == true ? validate_no_account! : validate_account_values!
      end

      def validate_no_account!
        acc_vals = form_attributes['directDeposit']

        raise_exception_on_invalid_account_values('account type') if acc_vals['accountType'].present?
        raise_exception_on_invalid_account_values('account number') if acc_vals['accountNumber'].present?
        raise_exception_on_invalid_account_values('routing number') if acc_vals['routingNumber'].present?
        if acc_vals['financialInstitutionName'].present?
          raise_exception_on_invalid_account_values('financial institution name')
        end
      end

      def raise_exception_on_invalid_account_values(account_detail)
        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "If the claimant has no account the #{account_detail} field must be left empty."
        )
      end

      def validate_account_values!
        direct_deposit_account_vals = form_attributes['directDeposit']
        return if direct_deposit_account_vals['noAccount']

        valid_account_types = %w[CHECKING SAVINGS]
        account_type = direct_deposit_account_vals&.dig('accountType')
        account_number = direct_deposit_account_vals&.dig('accountNumber')
        routing_number = direct_deposit_account_vals&.dig('routingNumber')

        form_object_desc = 'direct deposit'

        if account_type.blank? || valid_account_types.exclude?(account_type)
          raise_exception_if_value_not_present('account type (CHECKING/SAVINGS)', form_object_desc)
        end
        raise_exception_if_value_not_present('account number', form_object_desc) if account_number.blank?
        raise_exception_if_value_not_present('routing number', form_object_desc) if routing_number.blank?
      end

      def raise_exception_if_value_not_present(val, form_obj_description)
        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "The #{val} is required for #{form_obj_description}."
        )
      end

      def validate_claim_process_type_bdd!
        claim_date = Date.parse(CLAIM_DATE.to_s)
        service_information = form_attributes['serviceInformation']
        active_dates = service_information['servicePeriods']&.pluck('activeDutyEndDate')
        active_dates << service_information&.dig('federalActivation', 'anticipatedSeparationDate')

        unless active_dates.compact.any? do |a|
          next unless date_is_valid?(a, 'servicePeriods.activeDutyEndDate')

          Date.strptime(a, '%Y-%m-%d').between?(claim_date.next_day(BDD_LOWER_LIMIT),
                                                claim_date.next_day(BDD_UPPER_LIMIT))
        end
          raise ::Common::Exceptions::UnprocessableEntity.new(
            detail: "Must have an activeDutyEndDate or anticipatedSeparationDate between #{BDD_LOWER_LIMIT}" \
                    " & #{BDD_UPPER_LIMIT} days from claim date."
          )
        end
      end

      private

      def bdd_claim?
        claim_process_type = form_attributes['claimProcessType']
        claim_process_type == 'BDD_PROGRAM'
      end

      # Either date could be in MM-YYYY or MM-DD-YYYY format
      def begin_date_after_end_date_with_mixed_format_dates?(begin_date, end_date)
        # figure out if either has the day and remove it to compare
        if type_of_date_format(begin_date) == 'yyyy-mm-dd'
          begin_date = remove_chars(begin_date.dup)
        elsif type_of_date_format(end_date) == 'yyyy-mm-dd'
          end_date = remove_chars(end_date.dup)
        end
        Date.strptime(begin_date, '%Y-%m') > Date.strptime(end_date, '%Y-%m') # only > is an issue
      end

      def date_is_valid_against_current_time_after_check_on_format?(date)
        case type_of_date_format(date)
        when 'yyyy-mm-dd'
          param_date = Date.strptime(date, '%Y-%m-%d')
          now_date = Date.strptime(Time.zone.today.strftime('%Y-%m-%d'), '%Y-%m-%d')
        when 'yyyy-mm'
          param_date = Date.strptime(date, '%Y-%m')
          now_date = Date.strptime(Time.zone.today.strftime('%Y-%m'), '%Y-%m')
        when 'yyyy'
          param_date = Date.strptime(date, '%Y')
          now_date = Date.strptime(Time.zone.today.strftime('%Y'), '%Y')
        end
        param_date <= now_date # Since it is approximate we go with <=
      end

      # just need to know if day is present or not
      def date_has_day?(date)
        !date.match(YYYY_YYYYMM_REGEX)
      end

      # which of the three types are we dealing with
      def type_of_date_format(date)
        DATE_FORMATS[date.length]
      end

      # removing the -DD from a YYYY-MM-DD date format to compare against a YYYY-MM date
      def remove_chars(str)
        str.sub(/-\d{2}\z/, '')
      end

      def date_regex_groups(date)
        date_object = date.match(/^(?:(?<year>\d{4})(?:-(?<month>\d{2}))?(?:-(?<day>\d{2}))*|(?<month>\d{2})?(?:-(?<day>\d{2}))?-?(?<year>\d{4}))$/) # rubocop:disable Layout/LineLength

        make_date_string(date_object, date.length)
      end

      def make_date_string(date_object, date_length)
        if date_length == 4
          "#{date_object[:year]}-01-01".to_date
        elsif date_length == 7
          "#{date_object[:year]}-#{date_object[:month]}-01".to_date
        else
          "#{date_object[:year]}-#{date_object[:month]}-#{date_object[:day]}".to_date
        end
      end

      def begin_date_is_after_end_date?(begin_date, end_date)
        date_regex_groups(begin_date) > date_regex_groups(end_date)
      end

      def duty_begin_date_is_after_approximate_begin_date?(begin_date, approximate_begin_date)
        return unless date_is_valid?(begin_date, 'servicePeriod.activeDutyBeginDate')

        date_regex_groups(begin_date) > date_regex_groups(approximate_begin_date)
      end

      # Will check for a real date including leap year
      def date_is_valid?(date, property)
        return if date.blank?

        raise_date_error(date, property) unless /^[\d-]+$/ =~ date # check for something like 'July 2017'
        return true if date.match(YYYY_YYYYMM_REGEX) # valid YYYY or YYYY-MM date

        date_y, date_m, date_d = date.split('-').map(&:to_i)

        if Date.valid_date?(date_y, date_m, date_d)
          true
        else
          raise_date_error(date, property)
        end
      end

      def raise_date_error(date, property)
        raise ::Common::Exceptions::UnprocessableEntity.new(
          detail: "#{date} is not a valid date for #{property}."
        )
      end
    end
  end
end
