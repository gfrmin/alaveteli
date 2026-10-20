#!/usr/bin/env bash
set -euo pipefail

SERVER="alaveteli@accessinfohk"
REMOTE_DIR="/var/www/alaveteli/classic"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MIGRATE=false
THEME_ONLY=false

usage() {
    cat <<'EOF'
Usage: deploy.sh [OPTIONS]

Deploy Access Info HK (Alaveteli) to the server.

Deploys origin/master of both repositories. master is protected, so
changes reach it only by merging a pull request; this script never pushes.

Options:
  --theme-only   Only deploy theme changes (faster — skips bundle/core pull)
  --migrate      Run database migrations (causes brief downtime)
  -h, --help     Show this help
EOF
    exit 0
}

for arg in "$@"; do
    case $arg in
        --migrate)    MIGRATE=true ;;
        --theme-only) THEME_ONLY=true ;;
        -h|--help)    usage ;;
        *) echo "Unknown option: $arg"; usage ;;
    esac
done

echo "=== Access Info HK Deploy ==="

# Show what will be deployed, and warn about local commits that won't be
for repo in "$SCRIPT_DIR" "$SCRIPT_DIR/lib/themes/accessinfohktheme"; do
    git -C "$repo" fetch --quiet origin master
    echo "--- $(basename "$(git -C "$repo" rev-parse --show-toplevel)"):" \
         "$(git -C "$repo" log -1 --format='%h %s' origin/master)"
    unmerged=$(git -C "$repo" rev-list --count origin/master..HEAD)
    if [ "$unmerged" -gt 0 ]; then
        echo "    warning: HEAD has $unmerged commit(s) not on origin/master;" \
             "merge a pull request to deploy them"
    fi
done

if [ "$THEME_ONLY" = true ]; then
    echo "--- Theme-only deploy on server..."
    ssh "$SERVER" bash <<'REMOTE'
set -euo pipefail
export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$HOME/.gem/ruby/3.2.2/bin:$PATH"
cd /var/www/alaveteli/classic

echo "Pulling theme..."
cd lib/themes/accessinfohktheme
git pull --ff-only origin master

cd /var/www/alaveteli/classic
echo "Precompiling assets..."
RAILS_ENV=production bundle exec rake assets:precompile
RAILS_ENV=production bundle exec rake assets:link_non_digest

echo "Restarting puma..."
sudo systemctl restart alaveteli-puma
REMOTE
else
    echo "--- Full deploy on server..."
    ssh "$SERVER" bash -s -- "$MIGRATE" <<'REMOTE'
set -euo pipefail
MIGRATE="$1"
export PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$HOME/.gem/ruby/3.2.2/bin:$PATH"
cd /var/www/alaveteli/classic

echo "Pulling alaveteli (master)..."
git fetch --quiet origin master
git checkout --quiet master
git merge --ff-only origin/master

echo "Pulling theme..."
cd lib/themes/accessinfohktheme
git pull --ff-only origin master
cd /var/www/alaveteli/classic

echo "Running deploy-before-down (bundle, themes, assets)..."
script/rails-deploy-before-down

if [ "$MIGRATE" = true ]; then
    echo "Stopping puma for migrations..."
    sudo systemctl stop alaveteli-puma
    echo "Running migrations + seeds..."
    script/rails-deploy-while-down
    echo "Starting puma..."
    sudo systemctl start alaveteli-puma
else
    echo "Restarting puma..."
    sudo systemctl restart alaveteli-puma
fi

echo "Restarting sidekiq..."
sudo systemctl restart alaveteli-sidekiq
REMOTE
fi

echo "=== Deploy complete ==="
