require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

require File.dirname(__FILE__) + '/../lib/configuration'
require File.dirname(__FILE__) + '/../lib/alaveteli_localization'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Alaveteli
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Disable new framework default has_many_inversing breaks some specs due to
    # an apparent regression in Rails
    config.active_record.has_many_inversing = false # 6.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(
      ignore: %w(
        acts_as_xapian
        assets
        core_ext
        custom_cops
        generators
        has_tag_string
        tasks
        themes
      )
    )

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    # config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    # config.i18n.default_locale = :de
    config.i18n.enforce_available_locales = true

    # Configure the default encoding used in templates for Ruby 1.9.
    config.encoding = "utf-8"

    # Use SQL instead of Active Record's schema dumper when creating the test database.
    # This is necessary if your schema can't be completely dumped by the schema dumper,
    # like if you have constraints or database-specific column types
    config.active_record.schema_format = :sql

    # Make Active Record use UTC-base instead of local time
    config.active_record.default_timezone = :utc

    # Disable the IP spoofing warning. This is triggered by a conflict between
    # the CLIENT_IP and X_FORWARDED_FOR headers. If you're using the example
    # nginx config, that should be setting X_FORWARDED_FOR which is used in
    # preference to CLIENT_IP when the spoofing check is disabled. So this
    # setting should just prevent false positive errors when requests have
    # a CLIENT_IP header set.
    config.action_dispatch.ip_spoofing_check = false

    # This is the timezone that times and dates are displayed in
    # Note that having set a zone, the Active Record
    # time_zone_aware_attributes flag is on, so times from models
    # will be in this time zone
    config.time_zone = ::AlaveteliConfiguration.time_zone

    # Set the cache to use a memcached backend
    config.cache_store = :mem_cache_store,
      { namespace: "#{AlaveteliConfiguration.domain}_#{RUBY_VERSION}" }
    config.action_dispatch.rack_cache = nil

    # Use a real queuing backend for Active Job
    config.active_job.queue_adapter = :sidekiq

    config.after_initialize do |app|
      # Add a catch-all route to force routing errors to be handled by the application,
      # rather than by middleware.
      app.routes.append { match '*path', to: 'general#not_found', via: [:get, :post] }
    end

    config.autoload_paths << "#{Rails.root}/app/controllers/concerns"
    config.autoload_paths << "#{Rails.root}/app/models/concerns"

    # See Rails::Configuration for more options
    ENV['RECAPTCHA_SITE_KEY'] = AlaveteliConfiguration.recaptcha_site_key
    ENV['RECAPTCHA_SECRET_KEY'] = AlaveteliConfiguration.recaptcha_secret_key

    # Insert a bit of middleware code to prevent unneeded cookie setting.
    require "#{Rails.root}/lib/strip_empty_sessions"
    config.middleware.insert_before ::ActionDispatch::Cookies, StripEmptySessions, key: '_wdtk_cookie_session', path: "/", httponly: true
    Rails.backtrace_cleaner.add_silencer { |line| %r{^lib/strip_empty_sessions}.match?(line) }

    require "#{Rails.root}/lib/deeply_nested_params"
    config.middleware.insert Rack::Head, DeeplyNestedParams
    Rails.backtrace_cleaner.add_silencer { |line| %r{^lib/deeply_nested_params}.match?(line) }

    # Strip non-UTF-8 request parameters
    config.middleware.insert 0, Rack::UTF8Sanitizer

    # accessinfo.hk is behind Cloudflare, so without these request.remote_ip is
    # a Cloudflare edge rather than the visitor. https://www.cloudflare.com/ips/
    config.action_dispatch.trusted_proxies =
      ActionDispatch::RemoteIp::TRUSTED_PROXIES + %w(
      173.245.48.0/20
      103.21.244.0/22
      103.22.200.0/22
      103.31.4.0/22
      141.101.64.0/18
      108.162.192.0/18
      190.93.240.0/20
      188.114.96.0/20
      197.234.240.0/22
      198.41.128.0/17
      162.158.0.0/15
      104.16.0.0/13
      104.24.0.0/14
      172.64.0.0/13
      131.0.72.0/22
      2400:cb00::/32
      2606:4700::/32
      2803:f800::/32
      2405:b500::/32
      2405:8100::/32
      2a06:98c0::/29
      2c0f:f248::/32
    ).map { IPAddr.new(_1) }

    # Throttle abusive crawlers before they reach Rails / Xapian.
    config.middleware.use Rack::Attack

    # Allow the generation of full URLs in emails
    config.action_mailer.default_url_options = { host: AlaveteliConfiguration.domain }

    config.active_storage.variant_processor = :mini_magick
  end
end
