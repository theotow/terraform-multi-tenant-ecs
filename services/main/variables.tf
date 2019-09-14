variable "cluster_id" {
  description = "The ECS cluster ID"
  type        = string
}

variable "alb_arn" {
  description = "The alb arn"
  type        = string
}

variable "name" {
  description = "Name of project"
  type        = string
}

variable "name_prefix" {
  description = "name_prefix"
  type        = string
}

variable "environment" {
  description = "Name of environment"
  type        = string
}

variable "region" {
  description = "Name of region"
  type        = string
}

variable "image_url" {
  description = "image_url"
  type        = string
}
