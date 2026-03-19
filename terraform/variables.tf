variable "yandex_token" {
  type        = string
  description = "OAuth-токен или IAM-токен Yandex Cloud"
  sensitive   = true
}

variable "yandex_cloud_id" {
  type        = string
  description = "ID облака (yc config get cloud-id)"
}

variable "yandex_folder_id" {
  type        = string
  description = "ID каталога (yc config get folder-id)"
}

variable "ssh_public_key_path" {
  type        = string
  default     = "~/.ssh/id_rsa.pub"
  description = "Путь к публичному SSH-ключу"
}

variable "vm_name" {
  type    = string
  default = "devops-lab2-vm"
}

variable "zone" {
  type    = string
  default = "ru-central1-a"
}
