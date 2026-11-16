resource "yandex_vpc_network" "net" {
  name = "${local.stand}-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "${local.stand}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = [var.subnet_cidr]
}

data "yandex_compute_image" "base" {
  family = var.image_family
}

resource "yandex_compute_instance" "app" {
  for_each                  = toset([for i in range(var.vm_count) : tostring(i + 1)])
  name                      = "${local.stand}-app-${each.key}"
  hostname                  = "${local.stand}-app-${each.key}"
  zone                      = var.zone
  platform_id               = "standard-v3"
  allow_stopping_for_update = true

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
      image_id = data.yandex_compute_image.base.id
      size     = var.disk_size
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.app.id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      ssh_key      = var.ssh_public_key
      app_port     = var.app_port
      greeting     = var.greeting
      web_password = var.web_password
    })
  }

  labels = local.common_labels
}
resource "yandex_compute_disk" "data" {
  name   = "${local.stand}-data"
  zone   = var.zone
  size   = 10
  type   = "network-ssd"
  labels = local.common_labels

}


# машина не переезжала: изменился только её адрес в коде
moved {
  from = yandex_compute_instance.app
  to   = yandex_compute_instance.app["1"]
}
removed {
  from = yandex_compute_disk.hand

  lifecycle {
    destroy = false
  }
}
