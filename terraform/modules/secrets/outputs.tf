output "db_secret_arn"       { value = aws_secretsmanager_secret.db.arn }
output "rabbitmq_secret_arn" { value = aws_secretsmanager_secret.rabbitmq.arn }
