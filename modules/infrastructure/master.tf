resource "aws_iam_instance_profile" "master" {
  name = "${var.platform_name}-master-profile"
  role = "${aws_iam_role.master.name}"
}

resource "aws_launch_configuration" "master" {
  name_prefix   = "${var.platform_name}-master-"
  image_id      = "${data.aws_ami.node.id}"
  instance_type = "m4.large"
  ebs_optimized = true

  security_groups = [
    "${aws_security_group.node.id}",
    "${aws_security_group.master_public.id}",
  ]

  key_name             = "${aws_key_pair.platform.id}"
  user_data            = "${data.template_file.node_init.rendered}"
  iam_instance_profile = "${aws_iam_instance_profile.master.name}"
  spot_price           = "${var.upstream ? var.master_spot_price : ""}"

  lifecycle {
    create_before_destroy = true
  }

  root_block_device {
    volume_type           = "gp2"
    volume_size           = "100"
    delete_on_termination = true
  }
}

locals {
  master_target_group_arns = [
    "${aws_lb_target_group.master_public.arn}",
    "${aws_lb_target_group.master_public_insecure.arn}",
  ]

  master_infra_target_group_arns = [
    "${aws_lb_target_group.master_public.arn}",
    "${aws_lb_target_group.master_public_insecure.arn}",
    "${aws_lb_target_group.platform_public_insecure.arn}",
    "${aws_lb_target_group.platform_public.arn}",
  ]

  # https://github.com/hashicorp/terraform/issues/12453
  master_target_groups = [
    "${split(",", var.infra_node_count > 0 ? join(",", local.master_target_group_arns) : join(",", local.master_infra_target_group_arns))}",
  ]
}

resource "aws_autoscaling_group" "master" {
  vpc_zone_identifier       = ["${data.aws_subnet.node.*.id}"]
  name                      = "${var.platform_name}-master"
  max_size                  = "${var.master_count}"
  min_size                  = "${var.master_count}"
  desired_capacity          = "${var.master_count}"
  health_check_type         = "EC2"
  health_check_grace_period = 300
  force_delete              = true
  launch_configuration      = "${aws_launch_configuration.master.name}"

  target_group_arns = ["${local.master_target_groups}"]

  load_balancers = ["${aws_elb.master.name}"]

  tag {
    key                 = "kubernetes.io/cluster/${var.platform_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "Name"
    value               = "${var.platform_name}-master"
    propagate_at_launch = true
  }

  tag {
    key                 = "Role"
    value               = "node,master"
    propagate_at_launch = true
  }

  tag {
    key                 = "openshift_node_labels_region"
    value               = "${var.infra_node_count > 0 ? "master" : "infra"}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }
}
