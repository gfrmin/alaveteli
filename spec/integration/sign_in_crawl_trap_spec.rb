require 'spec_helper'

# Crawlers following links from the sign in page must reach a dead end. Each
# step used to mint a new PostRedirect, and link to a URL containing either its
# token or the current URL, so the set of URLs to crawl was unbounded.
RSpec.describe 'Sign in crawl trap', type: :request do
  let(:bare_sign_in_link) { 'class="sign_in_link" href="/profile/sign_in"' }

  describe 'the sign in link' do
    it 'does not point back at the sign in page it is on' do
      get '/profile/sign_in?r=%2Flist'
      expect(response.body).to include(bare_sign_in_link)
    end

    it 'does not point back at the password change page it is on' do
      get '/profile/change_password/new?pretoken=abc'
      expect(response.body).to include(bare_sign_in_link)
    end

    it 'returns to the current page from elsewhere' do
      get '/help/about'
      expect(response.body).to include('/profile/sign_in?r=%2Fhelp%2Fabout')
    end
  end

  describe 'a sign in page with nowhere specific to return to' do
    it 'does not create a PostRedirect' do
      expect { get '/profile/sign_in' }.not_to change(PostRedirect, :count)
    end

    it 'does not link to a password change page with a token' do
      get '/profile/sign_in'
      expect(response.body).not_to match(/pretoken=\w/)
    end

    it 'still lets a user sign in, returning to the front page' do
      user = FactoryBot.create(:user, password: 'jonespassword')
      get '/profile/sign_in'
      post '/profile/sign_in',
           params: { token: '',
                     user_signin: { email: user.email,
                                    password: 'jonespassword' } }
      expect(response).to redirect_to('/?post_redirect=1')
    end
  end

  describe 'a sign in page with somewhere to return to' do
    it 'keeps the destination through a sign in' do
      user = FactoryBot.create(:user, password: 'jonespassword')
      expect { get '/profile/sign_in?r=%2Flist' }.
        to change(PostRedirect, :count).by(1)
      token = PostRedirect.order(:id).last.token
      expect(response.body).to include("pretoken=#{token}")

      post '/profile/sign_in',
           params: { token: token,
                     user_signin: { email: user.email,
                                    password: 'jonespassword' } }
      expect(response).to redirect_to('/list?post_redirect=1')
    end
  end
end
