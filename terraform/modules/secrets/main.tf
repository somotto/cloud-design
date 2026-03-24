resource "aws_secretsmanager_secret" "db" {
  name                    = "${var.project_name}/db-credentials"
  description             = "Database credentials for orchestrator services"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    INVENTORY_DB_USER     = var.inventory_db_user
    INVENTORY_DB_PASSWORD = var.inventory_db_password
    INVENTORY_DB_NAME     = var.inventory_db_name
    BILLING_DB_USER       = var.billing_db_user
    BILLING_DB_PASSWORD   = var.billing_db_password
    BILLING_DB_NAME       = var.billing_db_name
  })
}

resource "aws_secretsmanager_secret" "rabbitmq" {
  name                    = "${var.project_name}/rabbitmq-credentials"
  description             = "RabbitMQ credentials for orchestrator services"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "rabbitmq" {
  secret_id = aws_secretsmanager_secret.rabbitmq.id
  secret_string = jsonencode({
    RABBITMQ_USER     = var.rabbitmq_user
    RABBITMQ_PASSWORD = var.rabbitmq_password
    RABBITMQ_QUEUE    = var.rabbitmq_queue
  })
}
