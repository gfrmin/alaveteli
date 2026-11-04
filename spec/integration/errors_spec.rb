require 'spec_helper'

RSpec.describe "When errors occur" do
  before(:each) do
    # This should happen automatically before each test but doesn't with these integration
    # tests for some reason.
    ActionMailer::Base.deliveries = []
  end

  context 'when considering all requests local (by default all in development)',
          local_requests: true do
    it 'should show a full trace for general errors' do
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise("An example error")
      get "/request/example"
      expect(response.body).to match('<div id="traces-0"')
      expect(response.body).to match('An example error')
    end
  end

  context 'when not considering all requests local', local_requests: false do
    it "should render a 404 for unrouteable URLs using the general/exception_caught template" do
      get "/frobsnasm"
      expect(response).to render_template('general/exception_caught')
      expect(response.code).to eq("404")
    end

    it "should render a 404 for users or bodies that don't exist using the general/exception_caught
            template" do
      ['/user/wobsnasm', '/body/wobsnasm'].each do |non_existent_url|
        get non_existent_url
        expect(response).to render_template('general/exception_caught')
        expect(response.code).to eq("404")
      end
    end

    it 'should render a 404 when given an invalid page parameter' do
      get '/body/list/all', params: { page: 'xoforvfmy' }
      expect(response).to render_template('general/exception_caught')
      expect(response.code).to eq('404')
      expect(response.body).to match("Sorry, we couldn't find that page")
    end

    it 'should handle non utf-8 parameters' do
      get('/%d3')
      expect(response).to render_template('general/exception_caught')
      expect(response.code).to eq('404')
      expect(response.body).to match("Sorry, we couldn't find that page")
    end

    context 'when the request body cannot be parsed' do
      let(:malformed_json) { '{"code":"x" ((X=~/.configrc6/a/xmrig.pid;' }

      def post_malformed_json(path)
        post path,
             params: malformed_json,
             headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      before do
        allow_any_instance_of(ApplicationController).
          to receive(:send_exception_notifications?).and_return(true)
      end

      it 'responds with an empty 400 on an unrouteable URL' do
        post_malformed_json '/api/v1/code/blocks/exec/code'
        expect(response.code).to eq('400')
        expect(response.body).to be_empty
      end

      it 'responds with an empty 400 on a routeable URL' do
        post_malformed_json '/profile/sign_in'
        expect(response.code).to eq('400')
        expect(response.body).to be_empty
      end

      it 'does not send an exception notification' do
        expect(ExceptionNotifier).not_to receive(:notify_exception)
        post_malformed_json '/api/v1/code/blocks/exec/code'
      end
    end

    it 'still renders a 404 for a well-formed POST to an unrouteable URL' do
      post '/api/v1/code/blocks/exec/code',
           params: '{"code":"x"}',
           headers: { 'CONTENT_TYPE' => 'application/json' }
      expect(response).to render_template('general/exception_caught')
      expect(response.code).to eq('404')
    end

    it "should render a 500 for general errors using the general/exception_caught template" do
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise("An example error")
      get "/request/example"
      expect(response).to render_template('general/exception_caught')
      expect(response.code).to eq("500")
    end

    it 'should render a 500 for json errors' do
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise("An example error")
      get "/request/example.json"
      expect(response.code).to eq('500')
    end

    it 'should render a 406 for a non-found xml request' do
      get "/frobsnasm.xml"
      expect(response.code).to eq('406')
    end

    it 'should notify of a general error' do
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise("An example error")
      get "/request/example"
      deliveries = ActionMailer::Base.deliveries
      expect(deliveries.size).to eq(1)
      mail = deliveries[0]
      expect(mail.body).to match(/An example error/)
    end

    it 'should log a general error' do
      expect(Rails.logger).to receive(:fatal)
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise("An example error")
      get "/request/example"
    end

    it 'should assign the locale for the general/exception_caught template' do
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise("An example error")
      get "/es"
      follow_redirect!
      get "/request/example"
      expect(response).to render_template('general/exception_caught')
      expect(response.body).to match('Lo sentimos, hubo un problema procesando esta página')
    end

    it 'should render a 403 with text body for attempts at directory listing for attachments' do
      info_request = FactoryBot.create(:info_request_with_pdf_attachment)
      id = info_request.id
      url_title = info_request.url_title
      prefix = id.to_s[0..2]
      msg_id = info_request.incoming_messages.first.id

      # make a fake cache
      cache_key_path = Rails.root.join(
        "cache/views/request/#{prefix}/#{id}/response/#{msg_id}/attach/html/1"
      )
      FileUtils.mkdir_p(cache_key_path)

      get "/request/#{url_title}/response/#{msg_id}/attach/html/1/"
      expect(response.body).to include('Directory listing not allowed')
      expect(response.code).to eq('403')

      get "/request/#{url_title}/response/#{msg_id}/attach/html"
      expect(response.body).to include('Directory listing not allowed')
      expect(response.code).to eq('403')
    end

    it "return a 403 for a JSON PermissionDenied error" do
      allow(InfoRequest).to receive(:find_by_url_title!).and_raise(ApplicationController::PermissionDenied)
      get "/request/example.json"
      expect(response.code).to eq('403')
    end

    it 'returns a 406 when an action does not support the format' do
      get '/version.invalid-format'
      expect(response.code).to eq('406')
    end
  end
end
