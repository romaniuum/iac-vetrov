output "app_urls" {
  value = {
    for key, vm in yandex_compute_instance.app :
    key => "http://${vm.network_interface.0.nat_ip_address}:${var.app_port}"
  }
}
