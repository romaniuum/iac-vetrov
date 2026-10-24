# Стенд ДЗ 2, вариант 09: сеть, две подсети, веб-серверы в двух зонах,
# целевая группа и сетевой балансировщик. Без сервера приложения и NAT-шлюза.

resource "yandex_vpc_network" "net" {
  name = "vetrov-09-hw2-net"
}

resource "yandex_vpc_subnet" "a" {
  name           = "vetrov-09-hw2-subnet-a"
  zone           = "ru-central1-d"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.19.1.0/24"]
}

resource "yandex_vpc_subnet" "b" {
  name           = "vetrov-09-hw2-subnet-b"
  zone           = "ru-central1-e"
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.19.2.0/24"]
}

data "yandex_compute_image" "os" {
  family = "debian-12"
}

resource "yandex_compute_instance" "web" {
  # По варианту 2 машины, третья добавлена по заявке. Номер машины входит в её адрес в состоянии
  # (web[0], web[1]), поэтому при уменьшении count удаляется последняя.
  count = 3

  name        = "vetrov-09-hw2-web-${count.index + 1}"
  hostname    = "vetrov-09-hw2-web-${count.index + 1}"
  platform_id = "standard-v3"
  # чётные номера в зону A, нечётные в зону B: машины чередуются по зонам
  zone = count.index % 2 == 0 ? "ru-central1-d" : "ru-central1-e"

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 2
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.os.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id = count.index % 2 == 0 ? yandex_vpc_subnet.a.id : yandex_vpc_subnet.b.id
    nat       = true
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      APP_PORT = 8027
      WORD     = "cloudlab"
      # открытая часть ключа не секрет; строкой, а не file(), чтобы
      # validate в пайплайне не искал ~/.ssh в контейнере
      SSH_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7hq/KoShnLcJ6XTCqvzk5sVIPaxbY39QuUNhPNEHw8 vetrov-09"
    })
  }

  labels = {
    owner = "vetrov-09"
    env   = "lab"
  }
}

resource "yandex_lb_target_group" "web" {
  name = "vetrov-09-hw2-tg"

  # по блоку target на каждую машину: при изменении count группа
  # перестраивается сама
  dynamic "target" {
    for_each = yandex_compute_instance.web
    content {
      subnet_id = target.value.network_interface.0.subnet_id
      # внутренний адрес: балансировщик ходит к машинам внутри сети,
      # с публичным nat_ip_address цели не станут HEALTHY
      address = target.value.network_interface.0.ip_address
    }
  }
}

resource "yandex_lb_network_load_balancer" "lb" {
  name = "vetrov-09-hw2-lb"

  listener {
    name        = "http"
    port        = 80
    target_port = 8027
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_lb_target_group.web.id

    healthcheck {
      name = "http"
      # проверка идёт на порт nginx, а не на 80, иначе все цели UNHEALTHY
      http_options {
        port = 8027
        path = "/"
      }
    }
  }

  labels = {
    owner = "vetrov-09"
    env   = "lab"
  }
}
