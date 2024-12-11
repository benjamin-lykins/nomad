

/*
This is mainly an example of some dependencies that you might need to create in order to use the AWS EBS CSI driver with Nomad.

This presumes you already have an existing Nomad cluster deployed in AWS. 

The following resources are created in this example- 
AWS:
- An IAM instance profile for Nomad servers and clients
- An IAM role for Nomad servers and clients
- An IAM role policy for auto-discovering Nomad instances (this is carry over from another example, but useful if you do not have an existing cluster and want to use the auto)
- An IAM role policy for mounting EBS volumes
- An AWS EBS volume for use with the AWS EBS CSI driver

Nomad:
- A Nomad job file for the AWS EBS CSI controller plugin (output to storage/job/plugin-ebs-controller.nomad.hcl)
- A Nomad job file for the AWS EBS CSI node plugin (output to storage/job/plugin-ebs-nodes.nomad.hcl)
- A Nomad volume registration file for the EBS volume (output to storage/volume/ebs-volume.nomad.hcl)

*/

variable "name" {
  type        = string
  description = "Name of the Nomad related resources."
}

variable "aws_availability_zone" {
  type        = string
  description = "Availability zone of Nomad Cluster, e.g. us-west-2a."
}

locals {
  tags = {
    Name      = var.name
    demo      = "aws-ebs-csi"
    terrafrom = true
  }
}


# Creates an IAM instance profile for Nomad with a name prefix derived from the variable `name`.
# The instance profile is associated with the IAM role specified by `aws_iam_role.nomad.name`.
# Tags for the instance profile are defined in the `local.tags` variable.
resource "aws_iam_instance_profile" "nomad" {
  name_prefix = "${var.name}-"
  role        = aws_iam_role.nomad.name
  tags        = local.tags
}

# Creates an AWS IAM role for Nomad with a specified name prefix, assume role policy, and tags.
# 
# Arguments:
# - name_prefix: A prefix for the name of the IAM role, derived from the variable `var.name`.
# - assume_role_policy: The assume role policy document for the IAM role, sourced from the data resource `data.aws_iam_policy_document.nomad.json`.
# - tags: A map of tags to assign to the IAM role, sourced from the local variable `local.tags`.
resource "aws_iam_role" "nomad" {
  name_prefix        = "${var.name}-"
  assume_role_policy = data.aws_iam_policy_document.nomad.json
  tags               = local.tags
}

# This data block defines an IAM policy document for Nomad.
# The policy grants the "Allow" effect for the "sts:AssumeRole" action.
# It specifies that the principal is a service with the identifier "ec2.amazonaws.com".
data "aws_iam_policy_document" "nomad" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# This resource creates an IAM role policy for auto-discovering Nomad instances for a cluster.
# The policy name is dynamically generated using the provided variable 'name'.
# The policy is attached to the IAM role identified by 'aws_iam_role.nomad.id'.
# The policy document is sourced from the data resource 'data.aws_iam_policy_document.auto_discover_cluster'.
resource "aws_iam_role_policy" "auto_discover_cluster" {
  name   = "${var.name}-auto-discover-cluster"
  role   = aws_iam_role.nomad.id
  policy = data.aws_iam_policy_document.auto_discover_cluster.json
}

# This data block defines an IAM policy document named "auto_discover_cluster".
# The policy grants permissions to describe EC2 instances, EC2 tags, and Auto Scaling groups.
# The permissions are granted to all resources ("*").
data "aws_iam_policy_document" "auto_discover_cluster" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeTags",
      "autoscaling:DescribeAutoScalingGroups",
    ]
    resources = ["*"]
  }
}

# This resource defines an IAM role policy named "mount-ebs-volumes".
# It attaches the policy to the IAM role identified by aws_iam_role.nomad.id.
# The policy document is sourced from the data.aws_iam_policy_document.mount_ebs_volumes resource.
resource "aws_iam_role_policy" "mount_ebs_volumes" {
  name   = "mount-ebs-volumes"
  role   = aws_iam_role.nomad.id
  policy = data.aws_iam_policy_document.mount_ebs_volumes.json
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
        image = "amazon/aws-ebs-csi-driver:v0.10.1"

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
        image = "amazon/aws-ebs-csi-driver:v0.10.1"

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
  filename = "${path.module}/storage/job/plugin-ebs-controller.nomad.hcl"
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