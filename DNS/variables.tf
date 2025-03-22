variable "records" {
  type        = map(string)
  description = "A map of DNS records to be added. Key is the hostname, value is the IP address."
}

variable "records_to_delete" {
  type        = map(string)
  description = "A map of DNS records to be explicitly deleted (for bootstrap removal)"
  default     = {}
}

variable "ttl" {
  type        = number
  description = "The TTL for the DNS records"
  default     = 8600
}

variable "cluster_domain" {
  type        = string
  description = "The domain for the cluster that all DNS records must belong to"
}

variable "infra_ips" {
  type        = list(string)
  description = "IP addresses of infrastructure nodes for load balancing"
  default     = []
}