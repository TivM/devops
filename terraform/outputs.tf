output "vm_public_ip" {
  value       = yandex_compute_instance.vm.network_interface[0].nat_ip_address
  description = "Публичный IP виртуальной машины (для SSH и Ansible)"
}

output "vm_ssh" {
  value       = "ssh ubuntu@${yandex_compute_instance.vm.network_interface[0].nat_ip_address}"
  description = "Команда для подключения по SSH"
}
