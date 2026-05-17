module AnalyticsHelper
  # helpers for embedding Google Analytics code
  #
  # Event categories and actions should be drawn from the list in the
  # lib/analytics_events.rb file (add your own there when making new ones)

  # Crawler / scripted-client User-Agent signature. Used to skip the PostHog
  # snippet on the server so we don't ship analytics JS to traffic we don't
  # want to count. Catches the obvious 95%; the remaining sophisticated
  # headless browsers are filtered client-side via the humanity_check event.
  BOT_UA_PATTERN = /
    bot | crawl | spider | slurp | fetcher | wget | curl | httpx? |
    monitor | pingdom | uptime | preview | prerender | lighthouse |
    headless | phantomjs | selenium | puppeteer | playwright |
    python-requests | python-urllib | go-http | java\/ |
    facebookexternalhit | embedly | quora | outbrain | nuzzel |
    discordbot | telegrambot | slackbot | whatsapp |
    gptbot | anthropic-ai | claude-web | claudebot | ccbot |
    perplexitybot | bingpreview | applebot
  /xi.freeze

  # Whether the current request should receive analytics JS. False for admin
  # sessions, obvious bot User-Agents, and requests without a User-Agent
  # header (raw HTTP clients, malicious scripts). Wraps the PostHog block in
  # `_before_head_end.html.erb`.
  def analytics_eligible?
    return false if @user&.is_admin?
    ua = request.user_agent.to_s
    return false if ua.blank?
    return false if ua.match?(BOT_UA_PATTERN)
    true
  end

  # Stable identifier for the visitor on this session. Signed-in users get
  # a deterministic id from User#id (so events follow them across devices);
  # anonymous visitors get a per-session UUID stored in the Rails session
  # cookie. Mirrored to the JS snippet via posthog.identify so server and
  # client events land on the same person.
  def analytics_distinct_id
    if current_user&.id
      "user_#{current_user.id}"
    else
      session[:posthog_distinct_id] ||= SecureRandom.uuid
    end
  end

  # Fire a server-side PostHog event. Safe to call when posthog_key is
  # blank (initializer skipped → config.x.posthog is nil → noop) and from
  # bot-flagged requests (skipped via analytics_eligible?). Anonymous
  # events are sent with $process_person_profile:false so they don't burn
  # person-profile quota under the identified_only mode set in the JS init.
  def track(event, properties = {})
    return unless analytics_eligible?
    return unless defined?(POSTHOG_CLIENT)

    props = {
      '$current_url' => request.url,
      '$lib' => 'posthog-ruby-server'
    }.merge(properties.stringify_keys)
    props['$process_person_profile'] = false unless current_user

    POSTHOG_CLIENT.capture(
      distinct_id: analytics_distinct_id,
      event: event.to_s,
      properties: props
    )
  rescue StandardError => e
    Rails.logger.warn "posthog track failed: #{e.class}: #{e.message}"
  end

  # Public: Constructs a String consisting of a Google Analytics (GA) tracking
  # event function call with the (mandatory) event category and action params
  # and optional label and value params.
  #
  # event_category - The String to be sent to GA as the tracking event category.
  #                  Ideally this should be an AnalyticsEvent::Category::THING
  #                  to avoid having magic strings everywhere
  # event_action   - The String to be sent to GA as the tracking event action.
  #                  Ideally this should be an AnalyticsEvent::Action::THING
  #                  to avoid having magic strings everywhere
  # options        - Hash of optional values, expects:
  #                   label           - String, an optional label for the event
  #                   label_is_script - Boolean, whether to treat the label
  #                                     String as literal or browser-
  #                                     interpreted (Javascript)
  #                   value           - Integer, Google insists that a numerical
  #                                     value param is supplied if label is used;
  #                                     if you don't care about this value and
  #                                     don't want to set it, leave it blank
  #                                     and a default of 1 will be sent
  #                  Any other supplied options will be ignored
  #
  # Examples
  #
  #   track_analytics_event("test", "button clicked")
  #   # => "if (ga) { ga('send','event','test','button clicked') };"
  #
  #   track_analytics_event("test", "vote button", :label => "sidebar")
  #   # => "if (ga) { ga('send','event','test','vote button','sidebar',1) };"
  #
  #   track_analytics_event("test", "Points Scored", :label => "Bonus", :value => 100)
  #   # => "if (ga) { ga('send','event','test','Points Scored','Bonus',100) };"
  #
  #   track_analytics_event("test",
  #                         "Embedded",
  #                         :label => "window.location.href",
  #                         :label_is_script => true)
  #   # => "if (ga) { ga('send','event','test','Embedded',window.location.href,1) };"
  #
  # Returns a string of a GA JavaScript function to drop into an :onclick handler
  def legacy_track_analytics_event(event_category, event_action, options={})
    begin
      value = if options[:value].nil?
        1
      else
        Integer(options[:value])
      end
    rescue ArgumentError
      raise ArgumentError, %Q(:value option must be an Integer: "#{ options[:value] }")
    end

    label_is_script = options[:label_is_script] == true
    label = options[:label]
    if label
      label_string = ",#{format_event_label(label, label_is_script)},#{value}"
    end
    event_args = "'#{event_category}','#{event_action}'#{label_string}"
    "if (ga) { ga('send','event',#{event_args}) };"
  end

  def track_analytics_event(event_category, event_action, options={})
    # noop, not implemented for GA4 yet
  end

  private

  # Private: Format the event label by wrapping in single quotes if it is
  # going to be used as a String literal (e.g. "'Button clicked'") or without if
  # it is a JavaScript string (e.g. "window.location.href") that needs to be run
  # and interpreted by the browser.
  #
  # label     - The label text (String) to by used
  # is_script - Boolean indicating whether the supplied label text is intended
  #             to be interpreted as JavaScript by the browser (defaults
  #             to false)
  #
  # Examples
  #
  #   format_event_label("Vote Button Clicked", false)
  #   # => "'Vote Button Clicked'"
  #
  #   format_event_label("window.top.location.href", true)
  #   # => "window.top.location.href"
  #
  # Returns the label String with or without containing single quotes,
  # depending on the value of the is_script param default behaviour:
  #   is_script is evaluated as false, string returned wrapped in single quotes)
  def format_event_label(label, is_script=false)
    if is_script
      label
    else
      "'#{label}'"
    end
  end
end
