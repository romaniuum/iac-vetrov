terraform {
  required_version = ">= 1.6"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "~> 0.220.0"
    }
  }
}

# Блок пустой специально: ключ, облако, каталог и зона приходят из
# переменных окружения YC_*. С путём к ключу здесь validate в пайплайне
# упал бы ещё до разбора ресурсов — в контейнере этого файла нет.
provider "yandex" {}
