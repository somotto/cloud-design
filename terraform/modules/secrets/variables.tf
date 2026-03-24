variable "project_name" {
  type = string
}

variable "inventory_db_user" {
  type      = string
  sensitive = true
}

variable "inventory_db_password" {
  type      = string
  sensitive = true
}

variable "inventory_db_name" {
  type = string
}

variable "billing_db_user" {
  type      = string
  sensitive = true
}

variable "billing_db_password" {
  type      = string
  sensitive = true
}

variable "billing_db_name" {
  type = string
}

variable "rabbitmq_user" {
  type      = string
  sensitive = true
}

variable "rabbitmq_password" {
  type      = string
  sensitive = true
}

variable "rabbitmq_queue" {
  type = string
}
