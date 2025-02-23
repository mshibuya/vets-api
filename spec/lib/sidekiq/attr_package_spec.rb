# frozen_string_literal: true

require 'rails_helper'
require 'sidekiq/attr_package'

RSpec.describe Sidekiq::AttrPackage do
  let(:redis_double) { instance_double(Redis::Namespace) }

  before do
    allow(Redis::Namespace).to receive(:new).and_return(redis_double)
    allow(redis_double).to receive(:set)
    allow(redis_double).to receive(:get)
    allow(redis_double).to receive(:del)
  end

  after do
    described_class.instance_variable_set(:@redis, nil)
  end

  describe '.create' do
    let(:attrs) { { foo: 'bar' } }
    let(:expected_key) { Digest::SHA256.hexdigest(attrs.to_json) }

    context 'when no expiration is provided' do
      it 'stores attributes in Redis and returns a key' do
        expect(redis_double).to receive(:set).with(expected_key, attrs.to_json, ex: 7.days)
        key = described_class.create(**attrs)
        expect(key).to eq(expected_key)
      end
    end

    context 'when an expiration is provided' do
      let(:expires_in) { 1.day }

      it 'stores attributes in Redis and returns a key' do
        expect(redis_double).to receive(:set).with(expected_key, attrs.to_json, ex: expires_in)
        key = described_class.create(expires_in:, **attrs)
        expect(key).to eq(expected_key)
      end
    end

    context 'when an error occurs' do
      let(:expected_error_message) { '[Sidekiq] [AttrPackage] create error: Redis error' }

      before do
        allow(redis_double).to receive(:set).and_raise('Redis error')
      end

      it 'raises an AttrPackageError' do
        expect do
          described_class.create(**attrs)
        end.to raise_error(Sidekiq::AttrPackageError).with_message(expected_error_message)
      end
    end
  end

  describe '.find' do
    let(:key) { 'some_key' }

    context 'when the key exists' do
      let(:json_attrs) { { foo: 'bar' }.to_json }

      before do
        allow(redis_double).to receive(:get).with(key).and_return(json_attrs)
      end

      it 'retrieves and deletes the attribute package from Redis' do
        expect(redis_double).to receive(:del).with(key)

        result = described_class.find(key)
        expect(result).to eq({ foo: 'bar' })
      end
    end

    context 'when the key does not exist' do
      before do
        allow(redis_double).to receive(:get).with(key).and_return(nil)
      end

      it 'returns nil' do
        expect(described_class.find(key)).to be_nil
      end
    end

    context 'when an error occurs' do
      let(:expected_error_message) { '[Sidekiq] [AttrPackage] find error: Redis error' }

      before do
        allow(redis_double).to receive(:get).with(key).and_raise('Redis error')
      end

      it 'raises an AttrPackageError and does not delete the package' do
        expect(redis_double).not_to receive(:del)
        expect do
          described_class.find(key)
        end.to raise_error(Sidekiq::AttrPackageError).with_message(expected_error_message)
      end
    end
  end
end
