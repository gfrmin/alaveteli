# Server-side PostHog client. Paired with the posthog-js snippet in the
# theme; lets controllers fire events for form submissions and state
# changes that don't show up client-side (the snippet only sees pageviews
# and autocapture clicks). The client buffers and flushes in a background
# thread so capture() calls don't slow down requests.
#
# Reads the same AlaveteliConfiguration.posthog_key as the JS snippet so
# events from both layers land on the same project. Skipped silently if
# the key is blank (development / staging without analytics) — in that
# case `defined?(POSTHOG_CLIENT)` is false and AnalyticsHelper#track noops.

return if AlaveteliConfiguration.posthog_key.blank?

require 'posthog-ruby'

POSTHOG_CLIENT = PostHog::Client.new(
  api_key: AlaveteliConfiguration.posthog_key,
  host: 'https://us.i.posthog.com',
  on_error: ->(_status, msg) { Rails.logger.warn("posthog: #{msg}") }
)

at_exit { POSTHOG_CLIENT.shutdown }
