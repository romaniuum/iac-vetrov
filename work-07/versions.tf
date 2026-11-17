terraform {
  required_version = ">= 1.11"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.220.0"
    }
  }

  backend "s3" {
    endpoints = { s3 = "https://storage.yandexcloud.net" }
    bucket    = "vetrov-09-tf-state"
    region    = "ru-central1"
    key       = "work-07/terraform.tfstate"

    use_lockfile                = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true
    skip_metadata_api_check     = true
  }
}

provider "yandex" {}
