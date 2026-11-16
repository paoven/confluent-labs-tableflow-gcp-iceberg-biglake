# Google Cloud side of the Tableflow BYOB setup. The bucket itself is expected to exist already (see README.md).
# Quick start: https://docs.confluent.io/cloud/current/topics/tableflow/get-started/quick-start-custom-storage-gcs.html

data "google_storage_bucket" "tableflow" {
  name = var.gcs_bucket_name
}

# The service account that Confluent Cloud impersonates
resource "google_service_account" "tableflow" {
  account_id   = "tableflow-quickstart-sa"
  display_name = "Confluent Cloud Tableflow"
}

# Allows Confluent Cloud's service account to impersonate 'tableflow' service account
resource "google_service_account_iam_member" "confluent-token-creator" {
  service_account_id = google_service_account.tableflow.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${confluent_provider_integration_authorization.gcp.gcp[0].google_service_account}"
}

# A single custom role with everything Tableflow needs, instead of roles/storage.objectUser, roles/storage.objectViewer
# and roles/biglake.admin (which also allows IAM policy changes on every catalog, namespace and table).
resource "google_project_iam_custom_role" "tableflow" {
  role_id     = "tableflowByob"
  title       = "Confluent Cloud Tableflow"
  description = "Write Tableflow data to GCS and register Iceberg tables in the Lakehouse runtime catalog"
  project     = var.customer_project_id
  permissions = [
    # GCS: write the materialized data and read table metadata
    "storage.objects.get",
    "storage.objects.list",
    "storage.objects.create",
    "storage.objects.delete",
    "storage.folders.create",
    # Lakehouse runtime catalog: create namespaces and register tables
    "biglake.catalogs.get",
    "biglake.catalogs.list",
    "biglake.namespaces.create",
    "biglake.namespaces.delete",
    "biglake.namespaces.get",
    "biglake.namespaces.list",
    "biglake.namespaces.update",
    "biglake.tables.create",
    "biglake.tables.delete",
    "biglake.tables.get",
    "biglake.tables.getData",
    "biglake.tables.list",
    "biglake.tables.register",
    "biglake.tables.update",
    "biglake.tables.updateData",
  ]
}

# BigLake permissions can only be granted at the project level, so the binding lives on the project. The condition keeps
# the storage permissions limited to the Tableflow bucket (other resource types, such as catalogs, are not affected).
resource "google_project_iam_member" "tableflow" {
  project = var.customer_project_id
  role    = google_project_iam_custom_role.tableflow.id
  member  = "serviceAccount:${google_service_account.tableflow.email}"

  condition {
    title       = "tableflow-bucket-only"
    description = "Limit GCS access to the Tableflow bucket"
    expression  = <<-EOT
      !(resource.type in ["storage.googleapis.com/Bucket", "storage.googleapis.com/Object", "storage.googleapis.com/Folder"]) ||
      resource.name == "projects/_/buckets/${data.google_storage_bucket.tableflow.name}" ||
      resource.name.startsWith("projects/_/buckets/${data.google_storage_bucket.tableflow.name}/")
    EOT
  }
}

# Lakehouse runtime catalog (formerly BigLake metastore). It must be a multiple-bucket catalog (CATALOG_TYPE_BIGLAKE):
# Tableflow doesn't support single-bucket catalogs (CATALOG_TYPE_GCS_BUCKET).
# Keep the default end-user credential mode: Tableflow doesn't support credential vending mode.
resource "google_biglake_iceberg_catalog" "main" {
  name         = data.google_storage_bucket.tableflow.name
  catalog_type = "CATALOG_TYPE_BIGLAKE"
  # Required for CATALOG_TYPE_BIGLAKE. The catalog can also use other buckets.
  default_location = "gs://${data.google_storage_bucket.tableflow.name}"
  credential_mode  = "CREDENTIAL_MODE_END_USER"
}
