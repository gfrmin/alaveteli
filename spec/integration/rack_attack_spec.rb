require 'spec_helper'

RSpec.describe 'Rack::Attack', type: :request do
  # Throttles count per fixed period; freeze time so the requests in an
  # example can't straddle a period boundary and split the count.
  around { |example| freeze_time { example.run } }

  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
  end

  let(:client_ip) { '203.0.113.42' }
  # As proxied in production: Cloudflare edge -> nginx on loopback -> puma
  let(:cloudflare_ip) { '104.23.190.145' }
  let(:headers) do
    { 'HTTP_CF_CONNECTING_IP' => client_ip,
      'HTTP_X_FORWARDED_FOR' => "#{client_ip}, #{cloudflare_ip}" }
  end

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

  it 'cannot be evaded by varying the CF-Connecting-IP header' do
    31.times do |i|
      get '/request/anything/similar',
          headers: headers.merge('HTTP_CF_CONNECTING_IP' => "198.51.100.#{i}")
    end
    expect(response.status).to eq(429)
  end

  describe 'sign in URLs that return to an authentication page' do
    [
      '/profile/sign_in?r=/profile/sign_in?r=/list',
      '/profile/sign_in?r=%2Fprofile%2Fsign_in%3Ftoken%3Dabc',
      '/profile/sign_in?r=%2Fprofile%2Fchange_password%2Fnew%3Fpretoken%3Dabc',
      '/profile/sign_in?locale=zh_HK&r=%2Fprofile%2Fsign_in%3Ftoken%3Dabc'
    ].each do |url|
      it "blocks #{url}" do
        get url, headers: headers
        expect(response.status).to eq(403)
      end
    end

    [
      '/profile/sign_in',
      '/profile/sign_in?r=%2Flist',
      '/profile/sign_in?r=/request/profile/sign_in',
      '/profile/sign_in?token=abc'
    ].each do |url|
      it "allows #{url}" do
        get url, headers: headers
        expect(response.status).to eq(200)
      end
    end
  end

  it 'still serves loopback traffic without throttling' do
    400.times do
      get '/', headers: { 'HTTP_CF_CONNECTING_IP' => '127.0.0.1' }
    end
    expect(response.status).not_to eq(429)
  end
end
