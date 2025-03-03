# frozen_string_literal: true

class PrescriptionDetails < Prescription
  attribute :cmop_division_phone, String
  attribute :in_cerner_transition, Boolean
  attribute :not_refillable_display_message, String
  attribute :cmop_ndc_number, String
  attribute :user_id, Integer
  attribute :provider_first_name, String
  attribute :provider_last_name, String
  attribute :remarks, String
  attribute :division_name, String
  attribute :modified_date, Common::UTCTime, sortable: { order: 'ASC' }
  attribute :institution_id, String
  attribute :dial_cmop_division_phone, String
  attribute :disp_status, String, sortable: { order: 'ASC' }
  attribute :ndc, String
  attribute :reason, String
  attribute :prescription_number_index, String
  attribute :prescription_source, String, sortable: { order: 'ASC' }
  attribute :disclaimer, String
  attribute :indication_for_use, String
  attribute :indication_for_use_flag, String
  attribute :category, String, sortable: { order: 'ASC' }
  attribute :tracking_list, Array[String]
  attribute :rx_rf_records, Array[String]
  attribute :tracking, Boolean
  attribute :orderable_item, String
  attribute :sorted_dispensed_date

  def sorted_dispensed_date
    has_refills = try(:rx_rf_records).present?
    last_refill_date = Date.new(0)

    if has_refills
      refills = rx_rf_records[0][1]

      refills.each do |r|
        last_dispensed = r.try(:[], :dispensed_date)
        next if last_dispensed.nil?

        refill_date = Date.parse(r.try(:[], :dispensed_date))
        last_refill_date = refill_date if refill_date.present? && refill_date > last_refill_date
      end
    end

    if has_refills && last_refill_date.present?
      last_refill_date.to_date
    elsif dispensed_date.present?
      dispensed_date.to_date
    else
      Date.new(0)
    end
  end
end
