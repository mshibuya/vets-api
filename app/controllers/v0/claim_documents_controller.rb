# frozen_string_literal: true

require 'pension_burial/tag_sentry'
require 'lgy/tag_sentry'

module V0
  class ClaimDocumentsController < ApplicationController
    service_tag 'claims-shared'
    skip_before_action(:authenticate)

    def create
      Rails.logger.info "Creating PersistentAttachment FormID=#{form_id}"

      attachment = klass.new(form_id:)
      # add the file after so that we have a form_id and guid for the uploader to use
      attachment.file = params['file']

      raise Common::Exceptions::ValidationErrors, attachment unless attachment.valid?

      attachment.save

      Rails.logger.info "Success creating PersistentAttachment FormID=#{form_id} AttachmentID=#{attachment.id}"

      render json: attachment
    rescue => e
      Rails.logger.error "Error creating PersistentAttachment FormID=#{form_id} AttachmentID=#{attachment.id} #{e}"
      raise e
    end

    private

    def klass
      case form_id
      when '21P-527EZ', '21P-530'
        PensionBurial::TagSentry.tag_sentry
        PersistentAttachments::PensionBurial
      when '21-686C', '686C-674'
        PersistentAttachments::DependencyClaim
      when '26-1880'
        LGY::TagSentry.tag_sentry
        PersistentAttachments::LgyClaim
      end
    end

    def form_id
      params[:form_id].upcase
    end
  end
end
