require 'spec_helper'

RSpec.describe ApplicationController do
  describe '#render_exception' do
    controller do
      def index
        render plain: 'rendered body' if params[:render_first]
        raise 'boom'
      end
    end

    before do
      # render_exception re-raises when consider_all_requests_local is true,
      # which it is in the test environment, so stub it to exercise the
      # production path.
      allow(Rails.application.config).
        to receive(:consider_all_requests_local).and_return(false)
      allow(controller).
        to receive(:send_exception_notifications?).and_return(false)
      allow(Rails.logger).to receive(:warn)
    end

    context 'when the response has already been rendered' do
      it 'does not raise AbstractController::DoubleRenderError' do
        expect { get :index, params: { render_first: true } }.
          to_not raise_error
      end

      it 'delivers the response that was already rendered' do
        get :index, params: { render_first: true }
        expect(response.body).to eq('rendered body')
      end

      it 'logs a warning naming the real exception' do
        get :index, params: { render_first: true }
        expect(Rails.logger).to have_received(:warn).
          with(/not rendering exception page for RuntimeError \(boom\)/)
      end
    end

    context 'when nothing has been rendered yet' do
      it 'renders the exception page with a 500' do
        get :index
        expect(response).to have_http_status(500)
      end

      it 'does not log the already-rendered warning' do
        get :index
        expect(Rails.logger).to_not have_received(:warn).
          with(/not rendering exception page/)
      end
    end
  end
end
