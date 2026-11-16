variable "confluent_cloud_api_key" {
  description = "Confluent Cloud API Key (also referred as Cloud API ID)"
  type        = string
}

variable "confluent_cloud_api_secret" {
  description = "Confluent Cloud API Secret"
  type        = string
  sensitive   = true
}

variable "customer_project_id" {
  description = "The GCP Project ID that hosts the GCS bucket and the Lakehouse runtime catalog"
  type        = string
}

variable "region" {
  description = "The GCP region of the Kafka cluster and the GCS bucket. The bucket must be in the same region as the cluster (dual-region buckets that include it also work, multi-region buckets do not)"
  type        = string
}

variable "gcs_bucket_name" {
  description = "The name of an existing, empty GCS bucket (see README.md). The multiple-bucket Lakehouse runtime catalog is created with the same name"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix prepended to the display names of the Confluent Cloud resources (environment, cluster, service accounts, API keys, integrations, connector). Leave empty for no prefix"
  type        = string
  default     = ""
}
