require 'spec_helper'
require 'integration/alaveteli_dsl'

RSpec.describe "Viewing requests with theme controller patches" do
  before do
    @session = without_login
  end

  it "renders a request awaiting response (triggers HK deadline code)" do
    info_request = FactoryBot.create(:info_request)
    using_session(@session) do
      browse_request(info_request.url_title)
      expect(page.status_code).to eq(200)
      expect(page).to have_content(info_request.title)
    end
  end

  it "renders a successful request (no deadline code)" do
    info_request = FactoryBot.create(:info_request, :successful)
    using_session(@session) do
      browse_request(info_request.url_title)
      expect(page.status_code).to eq(200)
      expect(page).to have_content(info_request.title)
    end
  end

  it "renders a request waiting clarification" do
    info_request = FactoryBot.create(:info_request, :waiting_clarification)
    using_session(@session) do
      browse_request(info_request.url_title)
      expect(page.status_code).to eq(200)
    end
  end

  it "renders an overdue request" do
    info_request = FactoryBot.create(:overdue_request)
    using_session(@session) do
      browse_request(info_request.url_title)
      expect(page.status_code).to eq(200)
    end
  end

  it "renders a very overdue request" do
    info_request = FactoryBot.create(:very_overdue_request)
    using_session(@session) do
      browse_request(info_request.url_title)
      expect(page.status_code).to eq(200)
    end
  end

  context "with HK deadline info" do
    it "shows deadline details for a waiting request" do
      info_request = FactoryBot.create(:info_request)
      using_session(@session) do
        browse_request(info_request.url_title)
        expect(page).to have_css('.hk-deadline-info')
        expect(page).to have_content('Interim reply (10 days)')
        expect(page).to have_content('Target response (21 days)')
      end
    end

    it "does not show deadline details for a successful request" do
      info_request = FactoryBot.create(:info_request, :successful)
      using_session(@session) do
        browse_request(info_request.url_title)
        expect(page).not_to have_css('.hk-deadline-info')
      end
    end
  end
end
