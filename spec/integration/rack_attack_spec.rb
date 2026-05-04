require 'spec_helper'

RSpec.describe 'Rack::Attack', type: :request do
  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  let(:client_ip) { '203.0.113.42' }
  let(:headers) { { 'HTTP_CF_CONNECTING_IP' => client_ip } }

  it 'allows requests under the /similar throttle' do
    30.times do
      get '/request/anything/similar', headers: headers
      expect(response.status).not_to eq(429)
    end
  end

  it 'returns 429 with Retry-After once the /similar throttle trips' do
    31.times { get '/request/anything/similar', headers: headers }
    expect(response.status).to eq(429)
    expect(response.headers['Retry-After']).to be_present
  end

  it 'still serves loopback traffic without throttling' do
    400.times do
      get '/', headers: { 'HTTP_CF_CONNECTING_IP' => '127.0.0.1' }
    end
    expect(response.status).not_to eq(429)
  end
end
