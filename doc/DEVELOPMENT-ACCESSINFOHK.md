# Developing accessinfo.hk

accessinfo.hk runs this fork of [Alaveteli](https://github.com/mysociety/alaveteli)
with the [accessinfohktheme](https://github.com/gfrmin/accessinfohktheme)
theme.

## Repositories and branches

| Repository | Production branch |
| --- | --- |
| `gfrmin/alaveteli` | `master`: the latest upstream release plus our patches |
| `gfrmin/accessinfohktheme` | `master` |

This follows upstream's git-flow convention, where `master` is what's
released and `develop` is upstream's integration branch. Both `master`
branches are the repository defaults and are protected: nobody can push to
them directly, including admins, so every change arrives through a pull
request.

The fork's other old branches (`develop`, `rails-3-develop`,
`production-*-patched`) are historical. Upstream retired `rails-3-develop`
long ago (see `doc/CHANGES.md`).

### Making a change

```bash
git switch -c hotfix/short-description master   # or feature/…
# commit, run the specs
git push -u origin HEAD
gh pr create --base master
gh pr merge --merge                              # once CI passes
./deploy.sh
```

### Taking an upstream release

Merge the release tag into a branch named after it, then open a PR:

```bash
git fetch upstream --tags
git switch -c release/0.46.9.0 master
git merge 0.46.9.0
```

## Setup

Clone the code into a directory of its own. The theme goes in a sibling
`alaveteli-themes` directory:

```bash
mkdir accessinfohk && cd accessinfohk
git clone https://github.com/gfrmin/alaveteli.git
cd alaveteli
script/setup-dev            # Docker or podman
script/setup-dev --native   # or: host Ruby and PostgreSQL
```

`script/setup-dev` clones the theme, writes `config/general.yml` (a copy of
`config/general.yml-example`, which already holds the accessinfo.hk
settings), creates the databases and loads sample data. Rerunning it is safe.

### Docker

Requires Docker 20+ or podman with `podman-compose`. Host ports 3000
(app), 6432 (PostgreSQL) and 1080 (MailHog) must be free, so stop any other
Alaveteli checkout's containers first.

```bash
docker compose up                                      # http://localhost:3000
docker compose run --rm app bundle exec rspec          # core specs
docker compose run --rm app bundle exec rspec lib/themes/accessinfohktheme/spec
docker compose run --rm app bin/rails console
```

### Native setup

Requires:

- Ruby 3.2 (production runs 3.2.2). With mise or rbenv, `echo 3.2.2 >
  .ruby-version` (the file is gitignored).
- PostgreSQL, running, with a superuser role named after your login (or set
  `username`/`password` in `config/database.yml` before running the script).
- `unrtf`, `tnef` and `pdftotext` (poppler); specs fail without them.
- Ideally the other tools in `config/packages` (Debian package names), which
  the app uses to convert attachments.

Then:

```bash
bin/rails server
bundle exec rspec
bundle exec rspec lib/themes/accessinfohktheme/spec
```

## Linting

The codebase isn't RuboCop-clean, so `bundle exec rubocop` with no
arguments always reports offences. Upstream CI only flags offences on
changed lines, so check the files you touched:

```bash
bundle exec rubocop path/to/changed_file.rb
```

## Deploying

`./deploy.sh` deploys `origin/master` of both repositories: it pulls,
bundles, precompiles and restarts on the server. It never pushes, so merge
your pull request first; it warns about local commits that aren't on
`origin/master`. It needs SSH access to `alaveteli@accessinfohk`.
`--theme-only` deploys only theme changes, and `--migrate` also runs
migrations.

## Troubleshooting

- **Docker: `cannot open shared object file` while loading a gem.** The
  `bundle` volume holds gems compiled against an older base image. Run
  `docker compose run --rm app bundle pristine`.
- **`config/general.yml` errors.** It must be a symlink to
  `general-accessinfohktheme.yml` in the same directory. Rerun
  `script/setup-dev` to repair it.
- **Mail in tests.** `config/test.yml` sets `SENDMAIL_PATH` to a stub that
  discards messages, so specs never deliver mail through the host's MTA.
