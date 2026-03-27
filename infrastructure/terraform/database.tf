# RDS subnet group (private subnets)

resource "aws_db_subnet_group" "postgres" {
  name       = "${var.app_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

# RDS PostgreSQL — pgvector is supported on Postgres 15+

resource "aws_db_instance" "postgres" {
  identifier        = "${var.app_name}-postgres"
  engine            = "postgres"
  engine_version    = "16.4"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "shantisangha"
  username          = var.db_username
  password          = random_password.db.result
  apply_immediately = true

  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible     = false
  deletion_protection     = true
  backup_retention_period = 7
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.app_name}-postgres-final-snapshot"

  # pgvector is installed via the application migration (CREATE EXTENSION vector)
  # RDS Postgres 16 ships with pgvector 0.7.0 built in
  parameter_group_name = aws_db_parameter_group.postgres.name
}

resource "aws_db_parameter_group" "postgres" {
  name   = "${var.app_name}-postgres16"
  family = "postgres16"
}

# ElastiCache subnet group (private subnets)

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.app_name}-redis-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

# ElastiCache Redis — single node for MVP

resource "aws_elasticache_cluster" "redis" {
  cluster_id           = "${var.app_name}-redis"
  engine               = "redis"
  engine_version       = "7.1"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.redis7"
  subnet_group_name    = aws_elasticache_subnet_group.redis.name
  security_group_ids   = [aws_security_group.redis.id]

  snapshot_retention_limit = 1
}
