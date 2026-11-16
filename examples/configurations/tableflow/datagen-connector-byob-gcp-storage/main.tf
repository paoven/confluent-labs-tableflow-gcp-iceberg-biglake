terraform {
  required_version = ">= 0.14.0"
  required_providers {
    google = {
      source = "hashicorp/google"
      # google_biglake_iceberg_catalog requires a recent version of the Google provider
      version = ">= 8.0.0"
    }
    confluent = {
      source  = "confluentinc/confluent"
      version = "2.93.0"
    }
  }
}

provider "confluent" {
  cloud_api_key    = var.confluent_cloud_api_key
  cloud_api_secret = var.confluent_cloud_api_secret
}

# Set GOOGLE_APPLICATION_CREDENTIALS environment variable to a path to a key file
# for Google TF Provider to work: https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/getting_started#adding-credentials
provider "google" {
  project = var.customer_project_id
  region  = var.region
}

resource "confluent_environment" "staging" {
  display_name = "${var.resource_prefix}Staging"

  stream_governance {
    package = "ESSENTIALS"
  }
}

data "confluent_schema_registry_cluster" "essentials" {
  environment {
    id = confluent_environment.staging.id
  }

  depends_on = [
    confluent_kafka_cluster.standard
  ]
}

# Update the config to use a cloud provider and region of your choice.
# https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster
resource "confluent_kafka_cluster" "standard" {
  display_name = "${var.resource_prefix}inventory"
  availability = "SINGLE_ZONE"
  cloud        = "GCP"
  // The GCS bucket must be in the same region as the cluster
  region = var.region
  standard {}
  environment {
    id = confluent_environment.staging.id
  }
}

// 'app-manager' service account is required in this configuration to create 'purchase' topic and grant ACLs
// to 'app-producer' and 'app-consumer' service accounts.
resource "confluent_service_account" "app-manager" {
  display_name = "${var.resource_prefix}app-manager"
  description  = "Service account to manage 'inventory' Kafka cluster"
}

resource "confluent_role_binding" "app-manager-kafka-cluster-admin" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "CloudClusterAdmin"
  crn_pattern = confluent_kafka_cluster.standard.rbac_crn
}

resource "confluent_role_binding" "app-manager-provider-integration-resource-owner" {
  principal   = "User:${confluent_service_account.app-manager.id}"
  role_name   = "ResourceOwner"
  crn_pattern = "${confluent_environment.staging.resource_name}/provider-integration=${confluent_provider_integration_setup.gcp.id}"
}

resource "confluent_api_key" "app-manager-kafka-api-key" {
  display_name = "${var.resource_prefix}app-manager-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }

  # The goal is to ensure that confluent_role_binding.app-manager-kafka-cluster-admin is created before
  # confluent_api_key.app-manager-kafka-api-key is used to create instances of
  # confluent_kafka_topic, confluent_kafka_acl resources.

  # 'depends_on' meta-argument is specified in confluent_api_key.app-manager-kafka-api-key to avoid having
  # multiple copies of this definition in the configuration which would happen if we specify it in
  # confluent_kafka_topic, confluent_kafka_acl resources instead.
  depends_on = [
    confluent_role_binding.app-manager-kafka-cluster-admin
  ]
}

resource "confluent_kafka_topic" "stock-trades" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  topic_name    = "stock-trades"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_service_account" "app-consumer" {
  display_name = "${var.resource_prefix}app-consumer"
  description  = "Service account to consume from 'purchase' topic of 'inventory' Kafka cluster"
}

resource "confluent_api_key" "app-consumer-kafka-api-key" {
  display_name = "${var.resource_prefix}app-consumer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-consumer' service account"
  owner {
    id          = confluent_service_account.app-consumer.id
    api_version = confluent_service_account.app-consumer.api_version
    kind        = confluent_service_account.app-consumer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
}

resource "confluent_service_account" "app-producer" {
  display_name = "${var.resource_prefix}app-producer"
  description  = "Service account to produce to 'purchase' topic of 'inventory' Kafka cluster"
}

resource "confluent_api_key" "app-producer-kafka-api-key" {
  display_name = "${var.resource_prefix}app-producer-kafka-api-key"
  description  = "Kafka API Key that is owned by 'app-producer' service account"
  owner {
    id          = confluent_service_account.app-producer.id
    api_version = confluent_service_account.app-producer.api_version
    kind        = confluent_service_account.app-producer.kind
  }

  managed_resource {
    id          = confluent_kafka_cluster.standard.id
    api_version = confluent_kafka_cluster.standard.api_version
    kind        = confluent_kafka_cluster.standard.kind

    environment {
      id = confluent_environment.staging.id
    }
  }
}

resource "confluent_kafka_acl" "app-producer-write-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.stock-trades.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-producer.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

// Note that in order to consume from a topic, the principal of the consumer ('app-consumer' service account)
// needs to be authorized to perform 'READ' operation on both Topic and Group resources:
// confluent_kafka_acl.app-consumer-read-on-topic, confluent_kafka_acl.app-consumer-read-on-group.
// https://docs.confluent.io/platform/current/kafka/authorization.html#using-acls
resource "confluent_kafka_acl" "app-consumer-read-on-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.stock-trades.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-consumer-read-on-group" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "GROUP"
  // The existing values of resource_name, pattern_type attributes are set up to match Confluent CLI's default consumer group ID ("confluent_cli_consumer_<uuid>").
  // https://docs.confluent.io/confluent-cli/current/command-reference/kafka/topic/confluent_kafka_topic_consume.html
  // Update the values of resource_name, pattern_type attributes to match your target consumer group ID.
  // https://docs.confluent.io/platform/current/kafka/authorization.html#prefixed-acls
  resource_name = "confluent_cli_consumer_"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-consumer.id}"
  host          = "*"
  operation     = "READ"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_api_key" "app-manager-tableflow-api-key" {
  display_name = "${var.resource_prefix}app-manager-tableflow-api-key"
  description  = "Tableflow API Key that is owned by 'app-manager' service account"
  owner {
    id          = confluent_service_account.app-manager.id
    api_version = confluent_service_account.app-manager.api_version
    kind        = confluent_service_account.app-manager.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app-manager-provider-integration-resource-owner,
  ]
}

# GCP provider integration (https://docs.confluent.io/cloud/current/integrations/provider-integrations/create-provider-integration-gc.html):
# Confluent Cloud impersonates the 'tableflow' Google service account (see gcp.tf).
resource "confluent_provider_integration_setup" "gcp" {
  environment {
    id = confluent_environment.staging.id
  }
  display_name = "${var.resource_prefix}gcs_tableflow_integration"
  cloud        = "GCP"
}

resource "confluent_provider_integration_authorization" "gcp" {
  provider_integration_id = confluent_provider_integration_setup.gcp.id
  environment {
    id = confluent_environment.staging.id
  }
  gcp {
    customer_google_service_account = google_service_account.tableflow.email
  }

  # Note: Confluent Cloud's service account is only known after this resource is created, so the
  # 'serviceAccountTokenCreator' binding (google_service_account_iam_member.confluent-token-creator in gcp.tf)
  # is created afterwards. Until then this resource may show warnings about the pending GCP setup.
}

resource "confluent_tableflow_topic" "stock-trades" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  display_name = confluent_kafka_topic.stock-trades.topic_name

  // Use BYOB Google Cloud Storage
  google_cloud_storage {
    bucket_name             = var.gcs_bucket_name
    provider_integration_id = confluent_provider_integration_setup.gcp.id
  }

  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }

  # The provider integration must be authorized and the Google service account must have access
  # to the bucket before an instance of confluent_tableflow_topic is created.
  depends_on = [
    confluent_provider_integration_authorization.gcp,
    google_service_account_iam_member.confluent-token-creator,
    google_project_iam_member.tableflow,
    # To avoid "Schemaless topic detected for topic stock-trades. Schemaless topics are not supported. Please specify a value schema." error
    confluent_connector.source
  ]
}

# Publishes the Iceberg tables to the Lakehouse runtime catalog (formerly BigLake metastore), so they can be queried from BigQuery.
# https://docs.confluent.io/cloud/current/topics/tableflow/how-to-guides/catalog-integration/integrate-with-lakehouse-runtime-catalog.html
resource "confluent_catalog_integration" "lakehouse-runtime-catalog" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  display_name = "${var.resource_prefix}tableflow-lakehouse-sync"
  biglake_metastore {
    provider_integration_id = confluent_provider_integration_setup.gcp.id
    gcp_project_id          = var.customer_project_id
    catalog_name            = google_biglake_iceberg_catalog.main.name
    // custom_namespace is optional; the namespace defaults to the Kafka cluster ID
  }

  credentials {
    key    = confluent_api_key.app-manager-tableflow-api-key.id
    secret = confluent_api_key.app-manager-tableflow-api-key.secret
  }

  depends_on = [
    confluent_tableflow_topic.stock-trades,
    google_project_iam_member.tableflow,
  ]
}

resource "confluent_service_account" "app-connector" {
  display_name = "${var.resource_prefix}app-connector567"
  description  = "Service account of S3 Sink Connector to consume from 'stock-trades' topic of 'inventory' Kafka cluster"
}


resource "confluent_kafka_acl" "app-connector-describe-on-cluster" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "CLUSTER"
  resource_name = "kafka-cluster"
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "DESCRIBE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-target-topic" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = confluent_kafka_topic.stock-trades.topic_name
  pattern_type  = "LITERAL"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-create-on-data-preview-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "data-preview"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "CREATE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_kafka_acl" "app-connector-write-on-data-preview-topics" {
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }
  resource_type = "TOPIC"
  resource_name = "data-preview"
  pattern_type  = "PREFIXED"
  principal     = "User:${confluent_service_account.app-connector.id}"
  host          = "*"
  operation     = "WRITE"
  permission    = "ALLOW"
  rest_endpoint = confluent_kafka_cluster.standard.rest_endpoint
  credentials {
    key    = confluent_api_key.app-manager-kafka-api-key.id
    secret = confluent_api_key.app-manager-kafka-api-key.secret
  }
}

resource "confluent_connector" "source" {
  environment {
    id = confluent_environment.staging.id
  }
  kafka_cluster {
    id = confluent_kafka_cluster.standard.id
  }

  // Block for custom *sensitive* configuration properties that are labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_sensitive = {}

  // Block for custom *nonsensitive* configuration properties that are *not* labelled with "Type: password" under "Configuration Properties" section in the docs:
  // https://docs.confluent.io/cloud/current/connectors/cc-datagen-source.html#configuration-properties
  config_nonsensitive = {
    "connector.class"          = "DatagenSource"
    "name"                     = "${var.resource_prefix}DatagenSourceConnector_0"
    "kafka.auth.mode"          = "SERVICE_ACCOUNT"
    "kafka.service.account.id" = confluent_service_account.app-connector.id
    "kafka.topic"              = confluent_kafka_topic.stock-trades.topic_name
    "output.data.format"       = "AVRO"
    "quickstart"               = "STOCK_TRADES"
    "tasks.max"                = "1"
  }

  depends_on = [
    confluent_kafka_acl.app-connector-describe-on-cluster,
    confluent_kafka_acl.app-connector-write-on-target-topic,
    confluent_kafka_acl.app-connector-create-on-data-preview-topics,
    confluent_kafka_acl.app-connector-write-on-data-preview-topics,
  ]
}

data "confluent_organization" "main" {}

resource "confluent_service_account" "app-reader" {
  display_name = "${var.resource_prefix}app-reader"
  description  = "Service account of Iceberg Reader applications or compute engines."
}

resource "confluent_api_key" "app-reader-tableflow-api-key" {
  display_name = "${var.resource_prefix}app-reader-tableflow-api-key"
  description  = "Tableflow API Key that is owned by 'app-reader' service account"
  owner {
    id          = confluent_service_account.app-reader.id
    api_version = confluent_service_account.app-reader.api_version
    kind        = confluent_service_account.app-reader.kind
  }

  managed_resource {
    id          = "tableflow"
    api_version = "tableflow/v1"
    kind        = "Tableflow"

    environment {
      id = confluent_environment.staging.id
    }
  }

  depends_on = [
    confluent_role_binding.app-reader-environment-admin,
  ]
}

// https://docs.confluent.io/cloud/current/topics/tableflow/operate/tableflow-rbac.html#access-to-tableflow-resources
resource "confluent_role_binding" "app-reader-environment-admin" {
  principal   = "User:${confluent_service_account.app-reader.id}"
  role_name   = "EnvironmentAdmin"
  crn_pattern = confluent_environment.staging.resource_name
}
