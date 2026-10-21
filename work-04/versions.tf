terraform {
  required_version = ">= 1.8"
  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.220.0"
    }
  }
}

provider "yandex" {
  # ключ лежит вне репозитория
  service_account_key_file = pathexpand("~/.yc-keys/vetrov-09-key.json")
  cloud_id                 = "b1gml3fap9c58mrhen4l"
  folder_id                = "b1ghu021jbhh3g86aicn"
  zone                     = "ru-central1-d"
}
