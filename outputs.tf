output "db_host" {
  description = "Endpoint of the RDS Proxy for connecting to the database"
  value       = module.rds_proxy.proxy_endpoint
}

output "db_port" {
  description = "Database port"
  value       = module.aurora.cluster_port
}

output "db_name" {
  description = "Database name"
  value       = module.aurora.cluster_database_name
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials"
  value       = tolist(module.aurora.cluster_master_user_secret)[0].secret_arn
}

output "db_clients_sg_id" {
  description = "Security group to attach to clients that need access to the database"
  value       = aws_security_group.db_clients.id
}