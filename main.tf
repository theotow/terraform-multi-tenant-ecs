provider "aws" {
  region = "<fill me>"
}

locals {
  name        = "complete-ecs"
  environment = "dev"
  region = "<fill me>"
  root_domain = "<fill me>"
  name_prefix = "${local.name}-${local.environment}"
}

terraform {
  backend "s3" {
    bucket = "<fill me>"
    key    = "<fill me>"
    region = "<fill me>"
  }
}

data "aws_route53_zone" "zone" {
  name         = "${local.root_domain}."
  private_zone = false
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.0"

  name = local.name_prefix

  cidr = "10.1.0.0/16"

  azs             = ["${local.region}a", "${local.region}b"]
  private_subnets = ["10.1.1.0/24", "10.1.2.0/24"]
  public_subnets  = ["10.1.11.0/24", "10.1.12.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

resource "aws_security_group" "alb_sec_group" {
  name        = "${local.name_prefix}-alb-sec-group"
  description = "${local.name_prefix}-alb-sec-group"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

resource "aws_security_group" "ec2_sec_group" {
  name        = "${local.name_prefix}-ec2_sec_group"
  description = "${local.name_prefix}-ec2_sec_group"
  vpc_id      = "${module.vpc.vpc_id}"

  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.alb_sec_group.id]
  }

  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
  }

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

resource "aws_lb" "alb" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sec_group.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

resource "aws_lb_target_group" "alb_target" {
  name     = "${local.name_prefix}-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "${module.vpc.vpc_id}"

  depends_on = [
    "aws_lb.alb"
  ]

  health_check {
    enabled = true
    path = "/"
    interval = 6
    timeout = 5
  }

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

resource "aws_lb_listener" "alb_listener_http" {
  load_balancer_arn = "${aws_lb.alb.arn}"
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_acm_certificate" "cert" {
  domain_name       = "${local.root_domain}"
  subject_alternative_names = ["*.${local.root_domain}"]
  validation_method = "DNS"

  tags = {
    Environment = local.environment
    Name        = local.name
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = "${aws_lb.alb.arn}"
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn  = "${aws_acm_certificate_validation.cert.certificate_arn}"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.alb_target.arn}"
  }
}

module "ecs" {
  source = "./modules/ecs"
  name   = local.name_prefix
  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

module "ec2-profile" {
  source = "./modules/ecs-instance-profile"
  name   = local.name_prefix
}

module "main-service" {
  source     = "./services/main"
  cluster_id = module.ecs.this_ecs_cluster_id
  alb_arn = aws_lb_target_group.alb_target.arn
  name = local.name
  name_prefix = local.name_prefix
  environment = local.environment
  region = local.region
  image_url = var.main_service_image_url
}

data "aws_ami" "amazon_linux_ecs" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-*-amazon-ecs-optimized"]
  }

  filter {
    name   = "owner-alias"
    values = ["amazon"]
  }

  tags = {
    Environment = local.environment
    Name        = local.name
  }
}

module "this" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "~> 3.0"

  name = local.name_prefix

  lc_name = local.name_prefix

  image_id             = data.aws_ami.amazon_linux_ecs.id
  instance_type        = "t2.micro"

  security_groups      = [aws_security_group.ec2_sec_group.id]
  iam_instance_profile = module.ec2-profile.this_iam_instance_profile_id
  user_data            = data.template_file.user_data.rendered

  asg_name                  = local.name_prefix
  vpc_zone_identifier       = module.vpc.private_subnets
  health_check_type         = "EC2"
  min_size                  = 1
  max_size                  = 1
  desired_capacity          = 1
  wait_for_capacity_timeout = 0

  tags = [
    {
      key                 = "Environment"
      value               = local.environment
      propagate_at_launch = true
    },
    {
      key                 = "Cluster"
      value               = local.name
      propagate_at_launch = true
    },
  ]
}

data "template_file" "user_data" {
  template = file("${path.module}/templates/user-data.sh")

  vars = {
    cluster_name = local.name_prefix
  }
}

resource "aws_ecr_repository" "repository" {
  name = "${local.name_prefix}-ecr-repo"
}

resource "aws_route53_record" "cert_validation" {
  name    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_name}"
  type    = "${aws_acm_certificate.cert.domain_validation_options.0.resource_record_type}"
  zone_id = "${data.aws_route53_zone.zone.id}"
  records = ["${aws_acm_certificate.cert.domain_validation_options.0.resource_record_value}"]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = "${aws_acm_certificate.cert.arn}"
  validation_record_fqdns = ["${aws_route53_record.cert_validation.fqdn}"]
}

resource "aws_route53_record" "www" {
  zone_id = "${data.aws_route53_zone.zone.id}"
  name    = "*.${local.root_domain}"
  type    = "A"

  alias {
    name                   = "${aws_lb.alb.dns_name}"
    zone_id                = "${aws_lb.alb.zone_id}"
    evaluate_target_health = true
  }
}