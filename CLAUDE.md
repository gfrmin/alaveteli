# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Alaveteli is an open-source platform for making Freedom of Information (FOI) requests. This is a fork (`gfrmin/alaveteli`) of `mysociety/alaveteli` (upstream remote configured). It powers accessinfo.hk (Hong Kong FOI platform). Rails 8.0 application, Ruby 3.2 (also tested on 3.3, 3.4).

**The main development branch is `rails-3-develop`, not `master` or `develop`.** Pull requests should target `rails-3-develop`.

## Development Commands

### Setup
```bash
git submodule update --init    # commonlib/ is a mySociety git submodule
bundle install
cp config/general.yml-example config/general.yml  # then edit settings
bin/rails db:migrate
bin/rails db:seed
```

### Running
```bash
bin/rails server               # Puma on port 3000
bin/rails console
```

### Docker / local development

This is the supported way to develop and test locally, and it works with
podman (`docker` and `docker compose` are podman shims on this machine).

One-time setup:
```bash
mkdir -p ../alaveteli-themes                    # sibling dir, mounted at /alaveteli-themes
git -C ../alaveteli-themes clone git@github.com:gfrmin/accessinfohktheme.git
./docker/bootstrap                              # config files, submodules, stock theme
cp config/general.yml-example config/general-accessinfohktheme.yml
ln -sfn general-accessinfohktheme.yml config/general.yml
ln -sfn ../../../alaveteli-themes/alavetelitheme lib/themes/alavetelitheme
./docker/setup                                  # build, bundle, migrate, seed, index
```

Day to day:
```bash
docker compose up                                        # http://localhost:3000
docker compose run --rm app bundle exec rspec <path>      # specs
docker compose run --rm app bundle exec rubocop           # lint
docker compose run --rm app bin/rails console
```
Services: `app`, `sidekiq`, `db` (PostgreSQL 13.5), `redis`, `smtp` (MailHog at 1080).

**The theme is a symlink, not a copy.** `script/switch-theme.rb` (run by
`docker/setup`) links `lib/themes/accessinfohktheme` to
`../alaveteli-themes/accessinfohktheme`, so edits in the theme repo are live
in the running app with no reinstall.

The `lib/themes/alavetelitheme` symlink is only there to satisfy core specs
that hardcode the stock theme's path (e.g. the `theme_asset_exists?` examples
in `spec/helpers/application_helper_spec.rb`). It is never loaded - in the
test environment `config/initializers/theme_loader.rb` loads only the theme
named by `ALAVETELI_TEST_THEME`.

### Theme specs

Theme specs live in the theme repo and run from the Alaveteli root:
```bash
docker compose run --rm app bundle exec rspec lib/themes/accessinfohktheme/spec
```

Three things a theme spec file must do, none of which fail loudly if omitted:

- **Set `ALAVETELI_TEST_THEME = 'accessinfohktheme'` before requiring
  `spec_helper`.** Without it the theme is not loaded and the specs silently
  run against an unthemed app. `require_theme` returns quietly when the named
  directory does not exist, so a wrong name looks identical to a right one.
- **Declare `type: :controller`** on controller specs. RSpec infers the type
  from the file path (`spec/controllers/`), which theme specs are not in, so
  `render_views`, `get` and `controller do` are otherwise undefined.
- **Stub message bodies after the last save.** Saving an `InfoRequest`
  reloads its `incoming_messages`, discarding stubs set on a detached
  message object; stub the instances the association yields.

### Testing
```bash
bundle exec rspec                              # Full suite
bundle exec rspec spec/path/to/file_spec.rb    # Single file
bundle exec rspec spec/path/to/file_spec.rb:42 # Specific test by line
COVERAGE=local bundle exec rspec               # With SimpleCov report
```

### Linting
```bash
bundle exec rubocop            # Run RuboCop
bundle exec rubocop -a         # Auto-fix
```

### Xapian Search Index
```bash
bundle exec rake xapian:update_index                # Incremental update
bundle exec rake xapian:destroy_and_rebuild_index   # Full rebuild
```

### Themes
```bash
bundle exec rake themes:install    # Clones theme repos into lib/themes/
```

### Background Jobs
Sidekiq with three queues: `default`, `xapian` (limit 1 worker), `low` (limit 1 worker). Config in `config/sidekiq.yml`.

## High-Level Architecture

### Core Models

The FOI request system centers on **InfoRequest**, which connects a **User** (requester) to a **PublicBody** (authority). Each request has **OutgoingMessages** (sent to the authority) and **IncomingMessages** (responses received). Every action is logged as an **InfoRequestEvent** (the primary Xapian search index target).

Key non-obvious details:
- **InfoRequest** uses `described_state` for status tracking and `prominence` for visibility control (normal/hidden/requester_only)
- **IncomingMessage** belongs to a **RawEmail** which stores the original MIME data via Active Storage
- **PublicBody** uses `acts_as_versioned` for edit history
- **User** uses bcrypt auth with `rolify` for roles and CanCanCan for authorization
- Shared concerns in `app/models/concerns/`: Taggable, Categorisable, Notable, RateLimited, MessageProminence

### FOI Request Flow

1. User creates request → selects PublicBody → OutgoingMessage created (status: `ready`)
2. Email sent to authority's `request_email` → OutgoingMessage status → `sent`
3. Authority replies → email arrives at `request-[ID]-[HASH]@domain` (HASH = SHA1 of ID + secret)
4. `MailHandler` parses MIME, extracts attachments (supports TNEF/PDF/Word/Excel/RTF) → IncomingMessage created
5. Request state → `waiting_classification` → user classifies response
6. Each step logs an InfoRequestEvent

### Mail Handling

- **Incoming**: `lib/mail_handler.rb` + `lib/alaveteli_mail_poller.rb` (POP3 polling)
- **Outgoing**: `OutgoingMailer` (to authorities), `RequestMailer` (user alerts), `TrackMailer` (subscriptions)
- Error tracking in `IncomingMessageError` table

### Search (Xapian)

`lib/acts_as_xapian/` — full-text search with faceted filtering by status, authority, filetype, tags, and date ranges. Indexes `InfoRequestEvent`, `PublicBody`, `User`. Database stored in `lib/acts_as_xapian/xapiandbs/`.

### Theming

Git-based themes cloned into `lib/themes/`. Can override views, CSS, JS, locales. This instance uses `accessinfohktheme`. Theme routes extend the main app via `$alaveteli_route_extensions`.

### Alaveteli Pro

Professional/paid tier in `app/models/alaveteli_pro/` and `app/controllers/alaveteli_pro/`. Includes batch requests, embargoes, Stripe subscription billing. Enabled via `ENABLE_ALAVETELI_PRO` config flag.

### Request States

- **Awaiting**: `waiting_response` → `overdue` (configurable days) → `very_overdue`
- **Classification**: `waiting_classification` (user must classify response)
- **Outcomes**: `successful`, `partially_successful`, `rejected`, `not_held`
- **Admin**: `requires_admin`, `vexatious`, `not_foi`

## Important Development Notes

### Database
- **PostgreSQL** with **SQL schema format** — schema lives in `db/structure.sql`, not `db/schema.rb`
- Migrations must be PostgreSQL-compatible (database-specific constraints are used)

### Configuration System
App config is in `config/general.yml` (not standard Rails config), loaded by `lib/configuration.rb`. Access settings as `AlaveteliConfiguration.SETTING_NAME` (module with `method_missing`). See `config/general.yml-example` for all 100+ settings with documentation.

### Testing Conventions
- Uses **both** global fixtures (`spec/fixtures/`) **and** FactoryBot — fixtures provide seeded reference data (users, roles, public_bodies loaded in foreign-key order), factories for test-specific records
- WebMock enabled for HTTP stubbing
- Capybara for feature/integration tests

### RuboCop
- `DisabledByDefault: true` — only explicitly enabled cops are enforced
- Target Ruby: 3.2
- Max line length: 80
- Excludes: `commonlib/`, `db/schema.rb`, `lib/themes/`, `node_modules/`, `vendor/`

### Custom Middleware
Inserted in `config/application.rb`:
- `StripEmptySessions` — prevents unneeded cookie setting
- `DeeplyNestedParams` — guards against deeply nested parameter attacks
- `Rack::UTF8Sanitizer` — sanitizes request encoding

### Custom Gems
In `gems/`:
- `alaveteli_features` — feature flag system
- `excel_analyzer` — Excel file analysis for Active Storage

### Internationalization
- `gettext` + `globalize` for translations
- 50+ locales in `locale/` and `locale_alaveteli_pro/`
- Translation management via Transifex

### Gem Versioning
Most gems locked at PATCH level (`~> 1.2.0`). GitHub forks use git refs (not branches) to prevent broken Gemfile.lock. See Gemfile header for full policy.

### Cron Jobs
See `config/crontab-example` — Xapian index updates (every 5 min), batch request sending (every 10 min), overdue alerts, embargo expiry, statistics generation.
