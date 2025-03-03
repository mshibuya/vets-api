# frozen_string_literal: true

class AttachmentSerializer < ActiveModel::Serializer
  attribute :id
  attribute :name
  attribute :message_id
  attribute :attachment_size

  link(:download) { v0_message_attachment_url(object.message_id, object.id) }
end
