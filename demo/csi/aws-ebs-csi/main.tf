terraform {
  # Required version of Terraform, due to cross variable validation.
  # https://www.hashicorp.com/blog/terraform-1-9-enhances-input-variable-validations
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "name" {
  type        = string
  description = "Name of the Nomad related resources."
  default     = "aws-ebs-csi"
}

variable "add_iam_mount_policy" {
  type        = bool
  description = <<EOF
  Toggling will add an IAM policy to an existing IAM role for Nomad to mount EBS volumes.
  add_iam_mount_policy = true will also require the aws_iam_role variable to be set to an existing IAM role for Nomad.
  EOF
  default     = false
}

variable "aws_iam_role" {
  type        = string
  description = "IAM role for Nomad to add the IAM policy to mount EBS volumes."
  validation {
    condition     = var.add_iam_mount_policy && length(var.aws_iam_role) > 0
    error_message = "IAM role must be a non-empty string."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region of Nomad Cluster, e.g. us-east-2."
  default     = "us-east-2"
}

variable "aws_availability_zone" {
  type        = string
  description = "Availability zone of Nomad Cluster, e.g. us-east-2a."
  default     = "us-east-2a"
}

locals {
  tags = {
    Name      = "aws-ebs-csi-demo"
    terrafrom = true
  }
}

# Fetches the IAM role information from AWS.
# The data block is looks for a aws_iam_role on the value of `var.add_iam_mount_policy`.
# If `var.add_iam_mount_policy` is true, the count is set to 1, utilizing the data block.
# If `var.add_iam_mount_policy` is false, the count is set to 0, and the data block is not used.
data "aws_iam_role" "nomad" {
  count = var.add_iam_mount_policy ? 1 : 0
  name  = var.aws_iam_role
}


# This resource defines an IAM role policy for mounting EBS volumes.
# It is conditionally created based on the value of the `aws_iam_generation` variable.
# If `aws_iam_generation` is true, the policy is created; otherwise, it is not.
# The policy is named "mount-ebs-volumes" and is attached to the IAM role specified by the `one(data.aws_iam_role.nomad.*.id)` expression.
# The policy document is defined by the `one(data.aws_iam_policy_document.*.mount_ebs_volumes.json)` expression.
resource "aws_iam_role_policy" "mount_ebs_volumes" {
  count  = var.add_iam_mount_policy ? 1 : 0
  name   = "mount-ebs-volumes"
  role   = one(data.aws_iam_role.nomad.*.id)
  policy = one(data.aws_iam_policy_document.mount_ebs_volumes.*.json)
}

# This data block defines an IAM policy document named "mount_ebs_volumes".
# The policy grants permissions to perform specific EC2 actions related to EBS volumes.
# 
# The allowed actions are:
# - ec2:DescribeInstances: Allows describing EC2 instances.
# - ec2:DescribeTags: Allows describing tags for EC2 resources.
# - ec2:DescribeVolumes: Allows describing EBS volumes.
# - ec2:AttachVolume: Allows attaching EBS volumes to instances.
# - ec2:DetachVolume: Allows detaching EBS volumes from instances.
# 
# The policy applies to all resources ("*").
data "aws_iam_policy_document" "mount_ebs_volumes" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "ec2:DescribeVolumes",
      "ec2:AttachVolume",
      "ec2:DetachVolume",
    ]
    resources = ["*"]
  }
}

# Creates an AWS EBS Volume resource for use with Nomad.
# 
# Arguments:
#   availability_zone - The availability zone where the EBS volume will be created. This is sourced from the variable `aws_availability_zone`.
#   size              - The size of the EBS volume in GiB. In this case, it is set to 40 GiB.
#   tags              - A map of tags to assign to the volume. This is sourced from the local variable `tags`.
resource "aws_ebs_volume" "aws_ebs_csi_demo" {
  availability_zone = var.aws_availability_zone
  size              = 40
  tags              = local.tags
}

resource "local_file" "controller" {
  content  = <<EOF
job "plugin-aws-ebs-controller" {
  datacenters = ["dc1"]

  group "controller" {
    task "plugin" {
      driver = "docker"

      config {
        image = "public.ecr.aws/ebs-csi-driver/aws-ebs-csi-driver:v1.38.1"

        args = [
          "controller",
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "--v=5",
        ]
      }

      csi_plugin {
        id        = "aws-ebs0"
        type      = "controller"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}

EOF
  filename = "${path.module}/storage/job/plugin-ebs-controller.nomad.hcl"
}

resource "local_file" "nodes" {
  content  = <<EOF
job "plugin-aws-ebs-nodes" {
  datacenters = ["dc1"]

  # you can run node plugins as service jobs as well, but this ensures
  # that all nodes in the DC have a copy.
  type = "system"

  group "nodes" {
    task "plugin" {
      driver = "docker"

      config {
        image = "public.ecr.aws/ebs-csi-driver/aws-ebs-csi-driver:v1.38.1"

        args = [
          "node",
          "--endpoint=unix://csi/csi.sock",
          "--logtostderr",
          "--v=5",
        ]

        # node plugins must run as privileged jobs because they
        # mount disks to the host
        privileged = true
      }

      csi_plugin {
        id        = "aws-ebs0"
        type      = "node"
        mount_dir = "/csi"
      }

      resources {
        cpu    = 500
        memory = 256
      }
    }
  }
}

EOF
  filename = "${path.module}/storage/job/plugin-ebs-nodes.nomad.hcl"
}

resource "local_file" "volume_registration" {
  content  = <<EOF
  # volume registration
type        = "csi"
id          = "ebs-demo"
name        = "ebs-demo"
external_id = "${aws_ebs_volume.aws_ebs_csi_demo.id}"
plugin_id   = "aws-ebs0"

capability {
  access_mode     = "single-node-writer"
  attachment_mode = "file-system"
}
EOF
  filename = "${path.module}/storage/volume/ebs-volume.nomad.hcl"
}


output "nomad" {
  value = <<EOF
  Following commands need to be run to deploy the CSI driver and register the EBS volume:

Run the controller job:
  nomad job run ${local_file.controller.filename}

Run the node job:
  nomad job run ${local_file.nodes.filename}

Register the volume:
  nomad volume register ${local_file.volume_registration.filename}

Check Status:
  nomad job status plugin-aws-ebs-controller  
  EOF
}