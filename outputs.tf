output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = local.name
}

output "alb_dns" {
  description = "alb_dns"
  value       = aws_lb.alb.dns_name
}

output "docker_registry" {
  description = "docker_registry"
  value       = aws_ecr_repository.repository.repository_url
}

output "root_domain" {
  description = "root_domain"
  value       = local.root_domain
}

