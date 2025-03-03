# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Claim Document Attachment', type: :request do
  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:error)
    allow(ClamScan::Client).to receive(:scan)
      .and_return(instance_double('ClamScan::Response', safe?: true))
  end

  context 'with a valid file' do
    let(:file) do
      fixture_file_upload('doctors-note.pdf')
    end

    it 'uploads a file' do
      params = { file:, form_id: '21P-527EZ' }
      expect do
        post('/v0/claim_documents', params:)
      end.to change(PersistentAttachment, :count).by(1)
      expect(response.status).to eq(200)
      resp = JSON.parse(response.body)
      expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])
      expect(PersistentAttachment.last).to be_a(PersistentAttachments::PensionBurial)
    end

    it 'uploads a file to the alternate route' do
      params = { file:, form_id: '21P-527EZ' }
      expect do
        post('/v0/claim_attachments', params:)
      end.to change(PersistentAttachment, :count).by(1)
      expect(response.status).to eq(200)
      resp = JSON.parse(response.body)
      expect(resp['data']['attributes'].keys.sort).to eq(%w[confirmation_code name size])
      expect(PersistentAttachment.last).to be_a(PersistentAttachments::PensionBurial)
    end

    it 'logs a successful upload' do
      expect(Rails.logger).to receive(:info).with('Creating PersistentAttachment FormID=21P-527EZ')
      expect(Rails.logger).to receive(:info).with(
        /^Success creating PersistentAttachment FormID=21P-527EZ AttachmentID=\d+/
      )
      expect(Rails.logger).not_to receive(:error).with(
        'Error creating PersistentAttachment FormID=21P-527EZ AttachmentID= Common::Exceptions::ValidationErrors'
      )

      params = { file:, form_id: '21P-527EZ' }
      expect do
        post('/v0/claim_documents', params:)
      end.to change(PersistentAttachment, :count).by(1)
    end
  end

  context 'with an invalid file' do
    let(:file) do
      fixture_file_upload('empty_file.txt', 'text/plain')
    end

    it 'does not upload the file' do
      params = { file:, form_id: '21P-527EZ' }
      expect do
        post('/v0/claim_attachments', params:)
      end.not_to change(PersistentAttachment, :count)
      expect(response.status).to eq(422)
      resp = JSON.parse(response.body)
      expect(resp['errors'][0]['title']).to eq('File size must not be less than 1.0 KB')
    end

    it 'logs the error' do
      expect(Rails.logger).to receive(:info).with('Creating PersistentAttachment FormID=21P-527EZ')
      expect(Rails.logger).not_to receive(:info).with(
        /^Success creating PersistentAttachment FormID=21P-527EZ AttachmentID=\d+/
      )
      expect(Rails.logger).to receive(:error).with(
        'Error creating PersistentAttachment FormID=21P-527EZ AttachmentID= Common::Exceptions::ValidationErrors'
      )

      params = { file:, form_id: '21P-527EZ' }
      post('/v0/claim_attachments', params:)
    end
  end
end
