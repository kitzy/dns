variable "AWS_REGION" {
  description = "AWS region where Route53 is managed"
  type        = string
}

variable "CLOUDFLARE_API_TOKEN" {
  description = "Cloudflare API token for managing DNS zones"
  type        = string
  sensitive   = true
}
