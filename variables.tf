variable "subscription_id" {
  description = "Azure subscription ID used for the demo."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group created for the demo."
  type        = string
  default     = "rg-s2s-ftd-customer-demo"
}

variable "location" {
  description = "Azure region for the demo."
  type        = string
  default     = "centralus"
}

variable "prefix" {
  description = "Short lowercase prefix used in resource names."
  type        = string
  default     = "s2sftdcust"

  validation {
    condition     = can(regex("^[a-z0-9]{2,20}$", var.prefix))
    error_message = "prefix must contain 2-20 lowercase letters or digits."
  }
}

variable "admin_username" {
  description = "Linux administrator username."
  type        = string
  default     = "azureuser"
}

variable "admin_ssh_public_key" {
  description = "SSH public key used for emergency console access. No inbound SSH rule is created."
  type        = string
  sensitive   = true
}

variable "vpn_shared_key" {
  description = "Customer-generated VPN pre-shared key. Supply through TF_VAR_vpn_shared_key."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.vpn_shared_key) >= 16
    error_message = "vpn_shared_key must contain at least 16 characters."
  }
}

variable "tags" {
  description = "Tags applied to all resources."
  type        = map(string)
  default = {
    workload    = "s2s-vpn-demo"
    environment = "demo"
    managed-by  = "terraform"
    purpose     = "customer-education"
  }
}
