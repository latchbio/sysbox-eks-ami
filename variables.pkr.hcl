variable "aws_target_regions" {
  type    = list(string)
  default = [
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
    "ca-central-1",
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "eu-north-1",
    "ap-northeast-1",
    "ap-northeast-2",
    "ap-northeast-3",
    "ap-south-1",
    "ap-southeast-1",
    "ap-southeast-2",
    "sa-east-1"
  ]
}

variable "img_name" {
  type    = string
  default = "plural"
}

variable "img_version" {
  type    = string
  default = "v0.1.0"
}

variable "architecture" {
  type    = string
  default = "amd64"
}

variable "ubuntu_version" {
  type    = string
  default = "focal-20.04"

  validation {
    condition     = can(regex("^\\w+-\\d+\\.\\d+$", var.ubuntu_version))
    error_message = "Invalid Ubuntu version: expected '{name}-{major}.{minor}'."
  }
}

variable "sysbox_version" {
  type    = string
  default = "0.6.2"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.sysbox_version))
    error_message = "Invalid Sysbox version: expected '{major}.{minor}.{patch}'."
  }
}

variable "k8s_version" {
  type    = string
  default = "1.23"

  validation {
    condition     = can(regex("^\\d+\\.\\d+$", var.k8s_version))
    error_message = "Invalid K8s version: expected '{major}.{minor}'."
  }
}
