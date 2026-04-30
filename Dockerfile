# syntax = docker/dockerfile:1
ARG ELIXIR_VERSION=1.19.5
ARG OTP_VERSION=28.4
ARG RUST_VERSION=1.91.0
ARG UBUNTU_VERSION=noble-20260210.1

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-ubuntu-${UBUNTU_VERSION}"
ARG RUNNER_IMAGE="ubuntu:${UBUNTU_VERSION}"

FROM rust:${RUST_VERSION}-slim-bookworm AS rust

FROM ${BUILDER_IMAGE} AS builder

RUN apt-get update -y && apt-get install -y --no-install-recommends \
  build-essential \
  git \
  nodejs \
  npm \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

ENV CARGO_HOME=/usr/local/cargo
ENV RUSTUP_HOME=/usr/local/rustup
ENV PATH=/usr/local/cargo/bin:${PATH}

COPY --from=rust /usr/local/cargo /usr/local/cargo
COPY --from=rust /usr/local/rustup /usr/local/rustup

WORKDIR /workspace

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

COPY mix.exs mix.lock techtree/
COPY .fly-build/elixir-utils elixir-utils
COPY .fly-build/design-system design-system

WORKDIR /workspace/techtree

RUN mix deps.get --only $MIX_ENV

COPY config config
RUN mix deps.compile

COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --prefix assets --omit=dev

COPY priv priv
COPY lib lib
COPY assets assets
COPY rel rel

RUN mix assets.deploy
RUN mix compile
RUN mix release

FROM ${RUNNER_IMAGE} AS runner

RUN apt-get update -y && apt-get install -y --no-install-recommends \
  libstdc++6 \
  openssl \
  libncurses6 \
  locales \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

WORKDIR /app
RUN useradd --create-home app

COPY --from=builder --chown=app:app /workspace/techtree/_build/prod/rel/tech_tree ./

USER app
ENV HOME=/app

CMD ["/app/bin/server"]
