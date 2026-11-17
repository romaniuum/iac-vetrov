variable "prefix" {
  description = "Личный префикс ресурсов"
  type        = string
}

variable "zone" {
  description = "Зона размещения стенда"
  type        = string
}

variable "subnet_cidr" {
  description = "Подсеть своего варианта"
  type        = string
}

variable "app_port" {
  description = "Порт приложения"
  type        = number

  validation {
    condition     = var.app_port > 1023 && var.app_port < 65536
    error_message = "Нужен порт из диапазона 1024–65535."
  }
}

variable "ssh_public_key" {
  description = "Открытый SSH-ключ управляющего компьютера"
  type        = string
}
