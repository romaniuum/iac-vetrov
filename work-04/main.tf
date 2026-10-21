# ---------- сеть ----------
resource "yandex_vpc_network" "net" {
  name = "vetrov-09-tf-net"
}

resource "yandex_vpc_subnet" "subnet" {
  name = "vetrov-09-tf-subnet"
  zone = "ru-central1-d"
  # ссылка на сеть: отсюда terraform понимает, что сеть создаётся первой
  network_id     = yandex_vpc_network.net.id
  v4_cidr_blocks = ["10.19.1.0/24"]
}

# ---------- образ ----------
# свежий образ семейства ищется при планировании, id руками не пишем
data "yandex_compute_image" "base" {
  family = "debian-12"
}

# ---------- машина ----------
resource "yandex_compute_instance" "app" {
  name                      = "vetrov-09-tf-app"
  hostname                  = "vetrov-09-tf-app"
  zone                      = "ru-central1-d"
  platform_id               = "standard-v3"
  allow_stopping_for_update = true

  resources {
    cores         = 2
    core_fraction = 20
    memory        = 4
  }

  scheduling_policy {
    preemptible = true
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.base.id
      size     = 25
      type     = "network-hdd"
    }
  }

  secondary_disk {
    disk_id = yandex_compute_disk.data.id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet.id
    nat       = true
  }

  metadata = {
    # templatefile подставляет ключ в шаблон, как envsubst во второй работе
    user-data = templatefile("${path.module}/cloud-init.tpl.yaml", {
      ssh_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
    })
  }

  labels = {
    env   = "lab"
    owner = "vetrov-09"
  }
}

# ---------- вывод ----------
output "app_ip" {
  description = "публичный адрес машины"
  value       = yandex_compute_instance.app.network_interface.0.nat_ip_address
}

# ---------- дополнительный диск ----------
resource "yandex_compute_disk" "data" {
  name = "vetrov-09-tf-data"
  zone = "ru-central1-d"
  size = 15
  type = "network-hdd"
}
