# frozen_string_literal: true

module SimpleFormsApi
  class VBA210845
    include Virtus.model(nullify_blank: true)

    attribute :data

    def initialize(data)
      @data = data
    end

    def metadata
      {
        'veteranFirstName' => @data.dig('veteran_full_name', 'first'),
        'veteranLastName' => @data.dig('veteran_full_name', 'last'),
        'fileNumber' => @data['veteran_va_file_number'].presence || @data['veteran_ssn'],
        'zipCode' => @data.dig('authorizer_address', 'postal_code') ||
          @data.dig('person_address', 'postal_code') ||
          @data.dig('organization_address', 'postal_code') ||
          '00000',
        'source' => 'VA Platform Digital Forms',
        'docType' => @data['form_number'],
        'businessLine' => 'CMP'
      }
    end

    def words_to_remove
      veteran_ssn + veteran_date_of_birth + authorizer_address + authorizer_phone +
        person_address + organization_address
    end

    private

    def veteran_ssn
      [
        data['veteran_ssn']&.[](0..2),
        data['veteran_ssn']&.[](3..4),
        data['veteran_ssn']&.[](5..8)
      ]
    end

    def veteran_date_of_birth
      [
        data['veteran_date_of_birth']&.[](0..3),
        data['veteran_date_of_birth']&.[](5..6),
        data['veteran_date_of_birth']&.[](8..9)
      ]
    end

    def authorizer_address
      [
        data.dig('authorizer_address', 'postal_code')&.[](0..4),
        data.dig('authorizer_address', 'postal_code')&.[](5..8)
      ]
    end

    def authorizer_phone
      [
        data['authorizer_phone']&.gsub('-', '')&.[](0..2),
        data['authorizer_phone']&.gsub('-', '')&.[](3..5),
        data['authorizer_phone']&.gsub('-', '')&.[](6..9)
      ]
    end

    def person_address
      [
        data.dig('person_address', 'postal_code')&.[](0..4),
        data.dig('person_address', 'postal_code')&.[](5..8)
      ]
    end

    def organization_address
      [
        data.dig('organization_address', 'postal_code')&.[](0..4),
        data.dig('organization_address', 'postal_code')&.[](5..8)
      ]
    end
  end
end
