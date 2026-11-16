output "resource-ids" {
  value = <<-EOT
  You have completed steps #1-4 from https://docs.confluent.io/cloud/current/topics/tableflow/get-started/quick-start-custom-storage-gcs.html

  Environment ID:   ${confluent_environment.staging.id}
  Kafka Cluster ID: ${confluent_kafka_cluster.standard.id}
  Kafka topic name: ${confluent_kafka_topic.stock-trades.topic_name}

  Service Accounts and their Kafka API Keys (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-manager.display_name}:                     ${confluent_service_account.app-manager.id}
  ${confluent_service_account.app-manager.display_name}'s Kafka API Key:     "${confluent_api_key.app-manager-kafka-api-key.id}"
  ${confluent_service_account.app-manager.display_name}'s Kafka API Secret:  "${confluent_api_key.app-manager-kafka-api-key.secret}"

  ${confluent_service_account.app-producer.display_name}:                    ${confluent_service_account.app-producer.id}
  ${confluent_service_account.app-producer.display_name}'s Kafka API Key:    "${confluent_api_key.app-producer-kafka-api-key.id}"
  ${confluent_service_account.app-producer.display_name}'s Kafka API Secret: "${confluent_api_key.app-producer-kafka-api-key.secret}"

  ${confluent_service_account.app-consumer.display_name}:                    ${confluent_service_account.app-consumer.id}
  ${confluent_service_account.app-consumer.display_name}'s Kafka API Key:    "${confluent_api_key.app-consumer-kafka-api-key.id}"
  ${confluent_service_account.app-consumer.display_name}'s Kafka API Secret: "${confluent_api_key.app-consumer-kafka-api-key.secret}"

  Step 4: Set up access to the Iceberg REST Catalog:

  Kafka Cluster ID: ${confluent_kafka_cluster.standard.id}
  REST Catalog Endpoint: "https://tableflow.${var.region}.gcp.confluent.cloud/iceberg/catalog/organizations/${data.confluent_organization.main.id}/environments/${confluent_environment.staging.id}"

  Service Account with "EnvironmentAdmin" role its Tableflow API Key (API Keys inherit the permissions granted to the owner):
  ${confluent_service_account.app-reader.display_name}:                        ${confluent_service_account.app-reader.id}
  ${confluent_service_account.app-reader.display_name}'s Tableflow API Key:    "${confluent_api_key.app-reader-tableflow-api-key.id}"
  ${confluent_service_account.app-reader.display_name}'s Tableflow API Secret: "${confluent_api_key.app-reader-tableflow-api-key.secret}"

  Step 4: Lakehouse runtime catalog integration:
  Catalog integration ID: ${confluent_catalog_integration.lakehouse-runtime-catalog.id}
  Catalog: ${google_biglake_iceberg_catalog.main.name} (project ${var.customer_project_id})

  Step 5: Query Iceberg tables from BigQuery (grant yourself roles/biglake.viewer on the project and roles/storage.objectViewer on the bucket first):
  SELECT * FROM `${var.customer_project_id}.${google_biglake_iceberg_catalog.main.name}.${confluent_kafka_cluster.standard.id}.${confluent_kafka_topic.stock-trades.topic_name}` LIMIT 10;
  Follow https://docs.confluent.io/cloud/current/topics/tableflow/how-to-guides/catalog-integration/integrate-with-lakehouse-runtime-catalog.html#query-tables-from-bigquery for details.

  Step 6: Query Iceberg tables from DuckDB (see README.md, section 7):
  export TABLEFLOW_API_KEY="${confluent_api_key.app-reader-tableflow-api-key.id}"
  export TABLEFLOW_API_SECRET="${confluent_api_key.app-reader-tableflow-api-key.secret}"
  export TABLEFLOW_REST_CATALOG_ENDPOINT="https://tableflow.${var.region}.gcp.confluent.cloud/iceberg/catalog/organizations/${data.confluent_organization.main.id}/environments/${confluent_environment.staging.id}"
  duckdb -ui -init duckdb-setup.sql
  SELECT * FROM iceberg_catalog."${confluent_kafka_cluster.standard.id}"."${confluent_kafka_topic.stock-trades.topic_name}" LIMIT 10;

  EOT

  sensitive = true
}
