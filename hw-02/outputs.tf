output "lb_url" {
  description = "адрес балансировщика"
  # listener и external_address_spec — множества, по индексу их не взять
  value = "http://${one(flatten([
    for l in yandex_lb_network_load_balancer.lb.listener : [
      for spec in l.external_address_spec : spec.address
    ]
  ]))}"
}

output "web_public_ips" {
  description = "публичные адреса веб-серверов"
  value       = yandex_compute_instance.web[*].network_interface.0.nat_ip_address
}

output "web_internal_ips" {
  description = "внутренние адреса веб-серверов (они же в целевой группе)"
  value       = yandex_compute_instance.web[*].network_interface.0.ip_address
}
