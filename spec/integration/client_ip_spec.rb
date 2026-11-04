require 'spec_helper'

RSpec.describe 'Client IP behind Cloudflare', type: :request do
  let(:visitor_ip) { '203.0.113.42' }
  let(:edge_ipv4) { '104.23.190.145' }
  let(:edge_ipv6) { '2606:4700:1::1' }

  def remote_ip_with(forwarded_for)
    get '/help/about', headers: { 'HTTP_X_FORWARDED_FOR' => forwarded_for }
    request.remote_ip
  end

  it 'uses the visitor rather than a Cloudflare IPv4 edge' do
    expect(remote_ip_with("#{visitor_ip}, #{edge_ipv4}")).to eq(visitor_ip)
  end

  it 'uses the visitor rather than a Cloudflare IPv6 edge' do
    expect(remote_ip_with("#{visitor_ip}, #{edge_ipv6}")).to eq(visitor_ip)
  end

  it 'ignores an address claimed by the visitor through Cloudflare' do
    forwarded_for = "198.51.100.7, #{visitor_ip}, #{edge_ipv4}"
    expect(remote_ip_with(forwarded_for)).to eq(visitor_ip)
  end

  it 'ignores an address claimed by a client connecting directly' do
    expect(remote_ip_with("198.51.100.7, #{visitor_ip}")).to eq(visitor_ip)
  end
end
