# frozen_string_literal: true

module MyHealth
  module V1
    class VaccinesController < MrController
      def index
        resource = client.list_vaccines
        render json: resource.to_json
      rescue ::MedicalRecords::PatientNotFound
        render body: nil, status: :accepted
      end

      def show
        vaccine_id = params[:id].try(:to_i)
        resource = client.get_vaccine(vaccine_id)
        render json: resource.to_json
      rescue ::MedicalRecords::PatientNotFound
        render body: nil, status: :accepted
      end
    end
  end
end
