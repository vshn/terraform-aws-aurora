# Terraform Module for AWS Aurora

Aurora MySQL Serverless v2 cluster behind an RDS Proxy, with Secrets Manager
managed master credentials, TLS enforcement and optional advanced auditing.

## Overview

Wraps the upstream [`rds-aurora`](https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws)
and [`rds-proxy`](https://registry.terraform.io/modules/terraform-aws-modules/rds-proxy/aws)
modules:

- Serverless v2, storage encrypted, engine version left to AWS so minor
  upgrades are not pinned in Terraform.
- An RDS Proxy as the only connection endpoint — `db_host` is the proxy, not the
  cluster.
- Master credentials managed by RDS and stored in Secrets Manager, with optional
  rotation.
- `require_secure_transport = ON` by default; optional `server_audit_logging`
  plus the slow query log.
- A self-managed RDS Proxy IAM role so its trust policy carries
  `aws:SourceAccount` (confused-deputy protection).
- A `db_clients` security group for consumers to attach — no ingress rules to
  maintain in the caller.

VPC, subnets, KMS keys and CloudWatch log groups belong to the calling stack.

## Architecture

```
clients (SG: db_clients) ──3306──▶ RDS Proxy ──3306──▶ Aurora MySQL Serverless v2
                                   proxy_subnet_ids     db_subnet_ids
                                        │
                                        └── Secrets Manager (master credentials)
```

Parameter groups: a cluster group (family `aurora-mysql8.0`, created only when
TLS enforcement or auditing is on, all parameters applied `immediate`) and a DB
group `aurora-params-<db_name>` setting `transaction_isolation = READ-COMMITTED`.

Destroying the cluster always takes a final snapshot named
`rds-aurora-<instance_name>-final`; `deletion_protection` is on by default.

## Inputs

| Name | Description | Type | Default | Required |
|---|---|---|---|---|
| `instance_name` | Cluster name, also used for the final snapshot identifier | `string` | — | yes |
| `environment` | Environment name, used for the DB subnet group | `string` | — | yes |
| `db_name` | Database name, also the naming prefix for proxy, SGs and parameter group | `string` | — | yes |
| `db_username` | Master username | `string` | — | yes |
| `vpc_id` | VPC for the cluster and proxy | `string` | — | yes |
| `db_subnet_ids` | Subnets for the DB subnet group (use isolated/intra subnets) | `list(string)` | `[]` | no |
| `proxy_subnet_ids` | Subnets for the RDS Proxy (must be reachable by clients) | `list(string)` | `[]` | no |
| `cluster_instance_class` | Instance class; keep `db.serverless` for Serverless v2 | `string` | `"db.serverless"` | no |
| `instances` | Cluster instances passed to the upstream module | `map(any)` | writer with Performance Insights | no |
| `serverless_min_capacity` | Minimum ACUs | `number` | `0.5` | no |
| `serverless_max_capacity` | Maximum ACUs | `number` | `4` | no |
| `backup_retention_period` | Days of automated backups; also the PITR window (AWS caps at 35) | `number` | `7` | no |
| `preferred_backup_window` | UTC backup window | `string` | `"02:00-03:00"` | no |
| `deletion_protection` | Deletion protection on the cluster | `bool` | `true` | no |
| `enforce_db_tls` | Set `require_secure_transport = ON` | `bool` | `true` | no |
| `enabled_cloudwatch_logs_exports` | Log types to export (`audit`, `error`, `general`, `slowquery`); `audit` needs `enable_audit_log` | `list(string)` | `[]` | no |
| `enable_audit_log` | Enable advanced auditing (`CONNECT,QUERY_DCL,QUERY_DDL`) and the slow query log | `bool` | `false` | no |
| `manage_master_user_password_rotation` | Terraform manages rotation of the master secret (see Notes) | `bool` | `true` | no |
| `master_user_password_rotation_automatically_after_days` | Days between rotations | `number` | `7` | no |
| `proxy_client_password_auth_type` | `MYSQL_CACHING_SHA2_PASSWORD` for MySQL 8.x, `MYSQL_NATIVE_PASSWORD` for 5.7 | `string` | `"MYSQL_CACHING_SHA2_PASSWORD"` | no |

## Outputs

| Name | Description |
|---|---|
| `db_host` | RDS Proxy endpoint — connect here, not to the cluster endpoint |
| `db_port` | Database port |
| `db_name` | Database name |
| `db_secret_arn` | Secrets Manager ARN of the master credentials |
| `db_clients_sg_id` | Security group to attach to clients needing database access |

## Usage

```hcl
module "aurora_database" {
  source = "git::https://github.com/vshn/terraform-aws-aurora.git?ref=v1.0.0"

  environment   = var.environment
  instance_name = "${var.environment}-instance"
  db_name       = var.db_name
  db_username   = "admin"

  vpc_id           = module.vpc.vpc_id
  db_subnet_ids    = module.vpc.intra_subnets
  proxy_subnet_ids = module.vpc.private_subnets

  backup_retention_period = 35

  enable_audit_log                = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "slowquery"]
}
```

Clients attach `module.aurora_database.db_clients_sg_id` and read the credentials
from `db_secret_arn`.

## Development

CI runs `terraform init -backend=false`, `terraform validate` and
`terraform fmt -check -recursive -diff`.

Merging a pull request labelled `bump:major`, `bump:minor` or `bump:patch` tags
the merge commit and creates a GitHub release; without such a label no release
is cut. Scaffolding under `.github/`, `renovate.json` and `.gitignore` is managed
by [`terraform-module-template`](https://github.com/vshn/terraform-module-template)
via cruft — do not edit it directly.
