locals {
  stand = "${var.prefix}-tf"
  common_labels = {
    env   = var.env
    owner = var.prefix
  }
}
