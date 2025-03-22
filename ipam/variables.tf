variable "hostnames" {
  type = set(string)
  description = "Set of hostnames requiring IP addresses"
}

variable "machine_cidr" {
  type = string
  description = "CIDR block to scan for free IP addresses"
}

variable "static_ip_addresses" {
  type    = list(string)
  default = []
  description = "List of static IP addresses to use instead of scanning"
}