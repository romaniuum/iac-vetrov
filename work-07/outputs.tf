output "public_ips" {
  description = "Публичные IP-адреса для инвентаря Ansible"
  value = {
    for name, instance in yandex_compute_instance.web :
    name => instance.network_interface[0].nat_ip_address
  }
}
