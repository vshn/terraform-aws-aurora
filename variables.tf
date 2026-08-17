
variable "instance_name" {
  type        = string
  description = "Name of the instance"
}

variable "environment" {
  type        = string
  description = "Environment"
}

variable "region" {
  type        = string
  description = "AWS Region"
  default     = "eu-central-2"
}

variable "db_name" {
  type        = string
  description = "Database name"
}

variable "db_username" {
  type        = string
  description = "Database username"
}

variable "cluster_instance_class" {
  type        = string
  description = "Instance Class"
  default     = "db.serverless"
}

variable "vpc_id" {
  type        = string
  description = "Id of the VPC used for the database"
}

variable "db_subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs used by database subnet group"
  default     = []
}

variable "proxy_subnet_ids" {
  type        = list(string)
  description = "List of subnet IDs used by proxy subnet group"
  default     = []
}

variable "backup_retention_period" {
  type        = number
  description = "The days to retain backups for"
  default     = 7
}

variable "preferred_backup_window" {
  type        = string
  description = "Daily time range during which automated backups are created if automated backups are enabled"
  default     = "02:00-03:00"
}

variable "deletion_protection" {
  type        = bool
  description = "If the DB instance should have deletion protection enabled."
  default     = true
}

variable "instances" {
  type        = map(any)
  description = "Map of cluster instances"
  default = {
    writer = {
      performance_insights_enabled          = true
      performance_insights_retention_period = 7
    }
  }
}

variable "serverless_min_capacity" {
  type    = number
  default = 0.5
}

variable "serverless_max_capacity" {
  type    = number
  default = 4
}

variable "manage_master_user_password_rotation" {
  type        = bool
  description = "Whether Terraform manages rotation of the RDS-managed master user secret. Defaults to true to match RDS's built-in rotation (the current behavior). To disable rotation, set this false and apply — destroying the rotation resource cancels rotation. The resource must exist first, so a fresh disable is: apply once with true, then apply with false."
  default     = true
}

variable "master_user_password_rotation_automatically_after_days" {
  type        = number
  description = "Days between automatic rotations of the RDS-managed master user secret (only used when manage_master_user_password_rotation is true)."
  default     = 7
}

variable "proxy_client_password_auth_type" {
  type        = string
  description = "Client password auth type for the RDS Proxy. Use MYSQL_CACHING_SHA2_PASSWORD for MySQL 8.x, MYSQL_NATIVE_PASSWORD for 5.7."
  default     = "MYSQL_CACHING_SHA2_PASSWORD"
}