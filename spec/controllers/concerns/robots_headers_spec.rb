require 'spec_helper'

RSpec.describe RobotsHeaders, type: :controller do
  controller(ApplicationController) do
    def index
      render plain: get_search_page_from_params.to_s
    end
  end

  it 'does not set no crawl headers on the first page' do
    get :index, params: { page: '1' }
    expect(response.headers['X-Robots-Tag']).to be_nil
  end

  it 'sets no crawl headers on later pages' do
    get :index, params: { page: '2' }
    expect(response.headers['X-Robots-Tag']).to eq 'noindex, nofollow'
  end

  it 'ignores a non-scalar page param' do
    get :index, params: { page: ['2'] }
    expect(response).to be_successful
    expect(response.headers['X-Robots-Tag']).to be_nil
    expect(response.body).to eq '1'
  end

  it 'ignores a hash page param' do
    get :index, params: { page: { a: '2' } }
    expect(response).to be_successful
    expect(response.body).to eq '1'
  end
end
