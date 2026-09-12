ARG RUBY_VERSION=3.2
FROM ruby:${RUBY_VERSION}-bookworm

ENV DOCKER 1
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -y && \
    apt-get install -y \
    elinks \
    ghostscript \
    libmagic-dev \
    pdftk \
    poppler-utils \
    postgresql-client \
    sendmail \
    tnef \
    unrtf \
    mutt

# Wait-for-it
RUN git clone https://github.com/vishnubob/wait-for-it.git /tmp/wait-for-it && \
    chmod +x /tmp/wait-for-it/wait-for-it.sh && \
    ln -s /tmp/wait-for-it/wait-for-it.sh /bin/wait-for-it

WORKDIR /alaveteli
RUN git config --global --add safe.directory /alaveteli

# Pin RubyGems to production's version (3.6.8). RubyGems 4 removed
# Gem::Specification#has_rdoc=, which the ruby-msg revision our Gemfile.lock
# pins (fae72e5) still calls on line 24 of its gemspec - so an unpinned
# `gem update --system` breaks every bundler invocation in the image.
# Upstream already moved that pin to 0c9ebb7, whose gemspec dropped the call.
# Bumping ours would fix the root cause, but it touches a locked gem on a
# production branch, so it needs a deploy-side check first.
RUN gem update --system 3.6.8

EXPOSE 3000
CMD wait-for-it db:5432 --strict -- ./docker/entrypoint.sh
