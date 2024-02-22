@default: help

@help:
  just --list --unsorted

@init:
  packer init .

@fmt:
  packer fmt .

@validate:
  packer validate .

@build:
  packer build sysbox-eks.pkr.hcl

@build-crio:
  docker build -t sysbox-eks-ami-crio . -f crio.Dockerfile
  docker run \
    --mount type=bind,source="$(realpath .)",target=/mnt \
    sysbox-eks-ami-crio \
    /usr/bin/env bash -c 'cp cri-o/bin/crio /mnt'
