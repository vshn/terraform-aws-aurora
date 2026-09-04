locals {
  # Cluster parameters combine TLS enforcement and (optionally) audit logging. Advanced auditing
  # params are dynamic, so apply_method "immediate" avoids a reboot.
  cluster_parameters = concat(
    var.enforce_db_tls ? [
      { name = "require_secure_transport", value = "ON", apply_method = "immediate" },
    ] : [],
    var.enable_audit_log ? [
      { name = "server_audit_logging", value = "1", apply_method = "immediate" },
      { name = "server_audit_events", value = "CONNECT,QUERY_DCL,QUERY_DDL", apply_method = "immediate" },
      { name = "slow_query_log", value = "1", apply_method = "immediate" },
    ] : [],
  )
}

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

  cluster_parameter_group = length(local.cluster_parameters) > 0 ? {
    family     = "aurora-mysql8.0"
    parameters = local.cluster_parameters
  } : null

  enabled_cloudwatch_logs_exports = var.enabled_cloudwatch_logs_exports

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

  # Use a self-managed role (below) so its trust policy carries confused-deputy protection
  create_iam_role = false
  role_arn        = aws_iam_role.rds_proxy.arn

  depends_on = [module.aurora]
}

data "aws_caller_identity" "current" {}

# RDS Proxy role — self-managed so the trust policy includes confused-deputy protection
# (aws:SourceAccount). Permissions mirror what the rds-proxy module would otherwise attach:
# decrypt the credentials secret via Secrets Manager and read it.
data "aws_iam_policy_document" "rds_proxy_assume" {
  statement {
    sid     = "RDSAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "rds_proxy" {
  statement {
    sid       = "DecryptSecrets"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["arn:aws:kms:*:*:key/*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.region}.amazonaws.com"]
    }
  }

  statement {
    sid    = "ListSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetRandomPassword",
      "secretsmanager:ListSecrets",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "GetSecrets"
    effect = "Allow"
    actions = [
      "secretsmanager:GetResourcePolicy",
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = [tolist(module.aurora.cluster_master_user_secret)[0].secret_arn]
  }
}

resource "aws_iam_role" "rds_proxy" {
  name_prefix        = "${var.db_name}-aurora-proxy-"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume.json
}

resource "aws_iam_role_policy" "rds_proxy" {
  name_prefix = "${var.db_name}-aurora-proxy-"
  role        = aws_iam_role.rds_proxy.id
  policy      = data.aws_iam_policy_document.rds_proxy.json
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
