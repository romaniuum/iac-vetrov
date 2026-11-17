data "yandex_vpc_network" "existing" {
  name = "leadflow"
}

resource "yandex_vpc_subnet" "subnet" {
  name           = "${var.prefix}-work-07-subnet"
  zone           = var.zone
  network_id     = data.yandex_vpc_network.existing.id
  v4_cidr_blocks = [var.subnet_cidr]
}

resource "yandex_vpc_security_group" "web" {
  name       = "${var.prefix}-work-07-sg"
  network_id = data.yandex_vpc_network.existing.id

  dynamic "ingress" {
    for_each = toset([22, var.app_port])
    content {
      protocol       = "TCP"
      port           = ingress.value
      v4_cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}

data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

resource "yandex_compute_instance" "web" {
  for_each    = toset(["web-1", "web-2"])
  name        = "${var.prefix}-work-07-${each.key}"
  hostname    = "${var.prefix}-${each.key}"
  zone        = var.zone
  platform_id = "standard-v3"

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
      image_id = data.yandex_compute_image.ubuntu.id
      size     = 10
      type     = "network-hdd"
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.web.id]
  }

  metadata = {
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      ssh_key = var.ssh_public_key
    })
  }
}
