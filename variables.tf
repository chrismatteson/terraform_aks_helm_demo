variable "location" {
  default = "eastus"
}

variable "agent_count" {
  default = 3
}

variable log_analytics_workspace_sku {
  default = "PerGB2018"
}

variable "ssh_public_key" {
  default = "~/.ssh/id_rsa.pub"
}

variable "tags" {
  type    = "map"
  default = {}
}
