variable "lb_ip_address" {
  type = string
}

variable "api_backend_addresses" {
  type = list(string)
}

variable "ingress_backend_addresses" {
  type = list(string)
}

variable "infra_backend_addresses" {
  type    = list(string)
  default = []
  description = "IP addresses of infrastructure nodes for load balancing"
}

variable "ssh_public_key_path" {
  type = string
}