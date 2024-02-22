# syntax = docker/dockerfile:1.4.1

from ubuntu:22.04 as base

workdir /tmp/docker-build/work/

shell [ \
  "/usr/bin/env", "bash", \
  "-o", "errexit", \
  "-o", "pipefail", \
  "-o", "nounset", \
  "-o", "verbose", \
  "-o", "errtrace", \
  "-O", "inherit_errexit", \
  "-O", "shift_verbose", \
  "-c" \
]

env TZ='Etc/UTC'
env LANG='en_US.UTF-8'

arg DEBIAN_FRONTEND=noninteractive

run --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
<<DKR
  apt-get update
  apt-get install \
    --yes \
    --no-install-recommends \
    gnupg \
    software-properties-common

  add-apt-repository --yes \
    ppa:longsleep/golang-backports
DKR

run --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
<<DKR
  apt-get update
  # todo(maximsmol): lock the golang version
  apt-get install \
    --yes \
    --no-install-recommends \
    git \
    build-essential \
    golang-go \
    libgpgme-dev
DKR

run --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
<<DKR
  git clone \
    --branch v1.22-sysbox \
    --depth 1 \
    --shallow-submodules \
    https://github.com/nestybox/cri-o.git \
    cri-o

  cd cri-o
  make binaries
DKR
