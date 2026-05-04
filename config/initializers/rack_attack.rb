# Rack::Attack throttles for endpoints that would otherwise let a misbehaving
# crawler exhaust file descriptors and Xapian connections.
#
# We've observed Amazonbot / SemrushBot paginating /request/*/similar?page=N
# fast enough to push the puma worker past its FD limit, surfacing as
# "Too many open files" from Xapian and as spurious LoadErrors when require
# runs out of FDs. robots.txt covers compliant bots; this catches the rest.

# Layered throttles for accessinfo.hk against abusive crawl traffic.
class Rack::Attack
  # Single-host deployment — in-process memory store is enough. If we ever
  # run multiple puma hosts this needs to move to Redis (the existing redis
  # client is already configured for sidekiq).
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Always allow loopback (health checks, sidekiq alerts, etc.)
  safelist('allow-localhost') do |req|
    req.ip == '127.0.0.1' || req.ip == '::1'
  end

  # Use the Cloudflare-supplied client IP when present, since accessinfo.hk
  # is fronted by Cloudflare and req.ip is the loopback proxy.
  # Subclassing Rack::Attack::Request overrides the request type used by
  # Rack::Attack throttle blocks.
  class Request < ::Rack::Request
    def remote_ip
      @remote_ip ||= (env['HTTP_CF_CONNECTING_IP'] ||
                      env['action_dispatch.remote_ip'].to_s.presence ||
                      ip).to_s
    end
  end

  # Tight throttle on the action that triggered the incident.
  throttle('similar/ip', limit: 30, period: 1.minute) do |req|
    req.remote_ip if req.path =~ %r{\A/request/[^/]+/similar\z}
  end

  # Other Xapian-backed search endpoints.
  throttle('search/ip', limit: 60, period: 1.minute) do |req|
    if req.path == '/search' ||
       req.path == '/list' ||
       req.path =~ %r{\A/body/[^/]+\z}
      req.remote_ip
    end
  end

  # Coarse backstop for everything else.
  throttle('all/ip', limit: 300, period: 1.minute, &:remote_ip)

  self.throttled_responder = ->(request) {
    match_data = request.env['rack.attack.match_data'] || {}
    retry_after = (match_data[:period] || 60).to_s
    [429,
     { 'Content-Type' => 'text/plain', 'Retry-After' => retry_after },
     ["Too many requests. Try again in #{retry_after} seconds.\n"]]
  }
end
