
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