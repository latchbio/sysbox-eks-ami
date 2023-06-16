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
  packer build -debug sysbox-eks.pkr.hcl
