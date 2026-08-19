module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "10.2.0"

  name              = var.instance_name
  engine            = "aurora-mysql"
  engine_version    = null
  storage_encrypted = true

  skip_final_snapshot       = false
  final_snapshot_identifier = "rds-aurora-${var.instance_name}-final"

  vpc_id  = var.vpc_id
  subnets = var.db_subnet_ids

  create_db_subnet_group = true
  db_subnet_group_name   = "rds-aurora-${var.environment}-${var.db_name}"

  cluster_db_instance_parameter_group_name = aws_db_parameter_group.aurora_parameter_group.name

  cluster_parameter_group = var.enforce_db_tls ? {
    family = "aurora-mysql8.0"
    parameters = [
      {
        name         = "require_secure_transport"
        value        = "ON"
        apply_method = "immediate"
      }
    ]
  } : null

  database_name                                          = var.db_name
  master_username                                        = var.db_username
  manage_master_user_password                            = true
  manage_master_user_password_rotation                   = var.manage_master_user_password_rotation
  master_user_password_rotate_immediately                = false
  master_user_password_rotation_automatically_after_days = var.master_user_password_rotation_automatically_after_days

  serverlessv2_scaling_configuration = {
    min_capacity = var.serverless_min_capacity
    max_capacity = var.serverless_max_capacity
  }

  cluster_instance_class = var.cluster_instance_class
  instances              = var.instances

  create_security_group = true
  port                  = 3306
  security_group_ingress_rules = {
    mysql_from_proxy = {
      referenced_security_group_id = aws_security_group.rds_proxy.id
      description                  = "MySQL from RDS Proxy"
    }
  }

  backup_retention_period = var.backup_retention_period
  preferred_backup_window = var.preferred_backup_window
  deletion_protection     = var.deletion_protection
}

module "rds_proxy" {
  source  = "terraform-aws-modules/rds-proxy/aws"
  version = "4.4.0"

  name                   = "${var.db_name}-aurora-proxy"
  engine_family          = "MYSQL"
  vpc_subnet_ids         = var.proxy_subnet_ids
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]

  target_db_cluster     = true
  db_cluster_identifier = module.aurora.cluster_id

  auth = {
    master = {
      description               = "Aurora Master Credentials (managed by Aurora)"
      secret_arn                = tolist(module.aurora.cluster_master_user_secret)[0].secret_arn
      iam_auth                  = "DISABLED"
      auth_scheme               = "SECRETS"
      client_password_auth_type = var.proxy_client_password_auth_type
    }
  }

  depends_on = [module.aurora]
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

# RDS Proxy Security Group
resource "aws_security_group" "rds_proxy" {
  name        = "rds-proxy-${var.db_name}"
  description = "Ingress 3306 from DB clients; egress to Aurora"
  vpc_id      = var.vpc_id
}

# Database Security Groups
resource "aws_security_group" "db_clients" {
  name        = "db-clients-${var.db_name}"
  description = "Security group to attach to clients that access the database."
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_db_clients" {
  security_group_id            = aws_security_group.rds_proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.db_clients.id
  description                  = "MySQL from DB clients SG"
}

resource "aws_vpc_security_group_egress_rule" "proxy_egress_aurora" {
  security_group_id            = aws_security_group.rds_proxy.id
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = module.aurora.security_group_id
  description                  = "Allow proxy to communicate with Aurora"
}

# Aurora Serverless v2
resource "aws_db_parameter_group" "aurora_parameter_group" {
  name        = "aurora-params-${var.db_name}"
  family      = "aurora-mysql8.0"
  description = "The default parameter group."

  parameter {
    name         = "transaction_isolation"
    value        = "READ-COMMITTED"
    apply_method = "immediate"
  }
}
