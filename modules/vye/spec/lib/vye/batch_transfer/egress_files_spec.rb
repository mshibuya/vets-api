# frozen_string_literal: true

require 'rails_helper'
require 'vye/batch_transfer/egress_files'

RSpec.describe VYE::BatchTransfer::EgressFiles do
  describe '#address_changes_filename' do
    it 'returns a string' do
      expect(VYE::BatchTransfer::EgressFiles.address_changes_filename).to be_a(String)
    end
  end

  describe '#direct_deposit_filename' do
    it 'returns a string' do
      expect(VYE::BatchTransfer::EgressFiles.direct_deposit_filename).to be_a(String)
    end
  end

  describe '#no_change_enrollment_filename' do
    it 'returns a string' do
      expect(VYE::BatchTransfer::EgressFiles.no_change_enrollment_filename).to be_a(String)
    end
  end
end
