### Notes

1. This example mirrors [Tableflow Quick Start with Iceberg Tables Using Your Storage on Google Cloud](https://docs.confluent.io/cloud/current/topics/tableflow/get-started/quick-start-custom-storage-gcs.html).
2. This example is the Google Cloud counterpart of the [datagen-connector-byob-aws-storage](https://github.com/confluentinc/terraform-provider-confluent/tree/master/examples/configurations/tableflow/datagen-connector-byob-aws-storage) example. It creates a Managed Datagen Source connector that produces messages to the `stock-trades` topic, enables Tableflow on it using your own Google Cloud Storage (GCS) bucket, and publishes the Iceberg tables to the [Lakehouse runtime catalog](https://docs.confluent.io/cloud/current/topics/tableflow/how-to-guides/catalog-integration/integrate-with-lakehouse-runtime-catalog.html) (formerly BigLake metastore) with the `confluent_catalog_integration` [resource](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_catalog_integration), so you can query the data from BigQuery.
3. The Kafka cluster is a Standard, single-zone cluster with public networking, so Terraform can reach the Kafka REST API from anywhere and no network setup is needed on the Google Cloud side beyond the bucket and IAM.
4. See [Sample Project for Confluent Terraform Provider](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/guides/sample-project) for step-by-step instructions on running this example.
5. See [Create a Google Cloud Provider Integration in Confluent Cloud](https://docs.confluent.io/cloud/current/integrations/provider-integrations/create-provider-integration-gc.html) for more details on provider integrations.
6. Google Cloud IAM changes can take a few minutes to propagate. If `confluent_provider_integration_authorization` fails validation or the catalog integration returns a 403, wait a few minutes and run `terraform apply` again.
7. The `terraform.tfvars` values are placeholders. Replace them with your own.

## Prepare your Google Cloud environment

Do these steps once, before running `terraform apply`.

### 1. Tools and credentials

- Install [Terraform](https://developer.hashicorp.com/terraform/install) and the [gcloud CLI](https://cloud.google.com/sdk/docs/install).
- Authenticate the Google provider, either with `gcloud auth application-default login` or by pointing `GOOGLE_APPLICATION_CREDENTIALS` to a service account key file. See [Google provider credentials](https://registry.terraform.io/providers/hashicorp/google/latest/docs/guides/getting_started#adding-credentials).
- Create a Confluent Cloud API key and secret (Cloud resource management) with the `OrganizationAdmin` or `EnvironmentAdmin` role.

```shell
export PROJECT_ID="<your-project-id>"
export REGION="us-central1"
gcloud config set project "$PROJECT_ID"
```

### 2. Enable the required APIs

```shell
gcloud services enable \
  storage.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  cloudresourcemanager.googleapis.com \
  biglake.googleapis.com \
  bigquery.googleapis.com
```

### 3. Permissions for the identity that runs Terraform

The identity needs permission to create and manage the following. The predefined roles in parentheses are a convenient starting point, narrow them for production:

- Service accounts and service account IAM bindings (`roles/iam.serviceAccountAdmin`).
- Project custom roles (`roles/iam.roleAdmin`) and project IAM bindings (`roles/resourcemanager.projectIamAdmin`).
- Bucket IAM bindings (`roles/storage.admin` on the bucket).
- Lakehouse runtime catalogs (`roles/biglake.admin`).

### 4. Create the GCS bucket

The bucket must be empty and in the same region as your Kafka cluster. Tableflow doesn't support multi-region buckets; a dual-region bucket that includes the cluster's region also works. Bucket names are globally unique.

```shell
export BUCKET_NAME="tableflow-quickstart-<unique-suffix>"
gcloud storage buckets create "gs://$BUCKET_NAME" \
  --location="$REGION" \
  --uniform-bucket-level-access
```

Set `gcs_bucket_name` to this name. Terraform will:

- create the `tableflow-quickstart-sa` service account that Confluent Cloud impersonates;
- create a custom role with the storage permissions (`storage.objects.{get,list,create,delete}`, `storage.folders.create`) and the Lakehouse runtime catalog permissions (`biglake.catalogs/namespaces/tables.*`) Tableflow needs, and grant it on the project. BigLake permissions can't be scoped to a single catalog, so an IAM condition limits the storage permissions to the bucket;
- let the Confluent Cloud service account that belongs to the provider integration impersonate it, with `roles/iam.serviceAccountTokenCreator`;
- create a multiple-bucket Lakehouse runtime catalog (`CATALOG_TYPE_BIGLAKE`) named like the bucket, with the default end-user credential mode (Tableflow doesn't support single-bucket catalogs or credential vending mode).

If you would rather create these resources yourself (for example, with your own IAM role), remove them from `gcp.tf` and keep only the bindings you manage elsewhere. Keep `google_service_account.tableflow` or replace its references with your own service account.

> A namespace in the Lakehouse runtime catalog can use only one bucket. If topics in the same cluster write to different buckets, contact Confluent Support before configuring the integration.

### 5. Run the example

```shell
terraform init
terraform plan
terraform apply
terraform output resource-ids
```

### 6. Query the table from BigQuery

Your account needs `roles/biglake.viewer` on the project and `roles/storage.objectViewer` on the bucket. Then, in BigQuery:

```sql
SELECT * FROM `<project_id>.<bucket_name>.<kafka_cluster_id>.stock-trades` LIMIT 10;
```

The namespace defaults to the Kafka cluster ID, and the table name is the topic name. Allow a few minutes for the first snapshot to be published; it may initially contain only the schema.

### 7. (Optional) Query the table from DuckDB

`duckdb-setup.sql` attaches the Tableflow Iceberg REST catalog to DuckDB, which then reads the data files from the bucket. Install [DuckDB](https://duckdb.org/docs/installation/) (for example, `brew install duckdb`), then export the `app-reader` service account's Tableflow API key and secret, and the `REST Catalog Endpoint`, which are all listed in `terraform output resource-ids`:

```shell
export TABLEFLOW_API_KEY="<app-reader Tableflow API key>"
export TABLEFLOW_API_SECRET="<app-reader Tableflow API secret>"
export TABLEFLOW_REST_CATALOG_ENDPOINT="<REST Catalog Endpoint>"
duckdb -ui -init duckdb-setup.sql
```

In the DuckDB UI, run:

```sql
SHOW ALL TABLES;
SELECT * FROM iceberg_catalog."<kafka_cluster_id>"."stock-trades" LIMIT 10;
```

Notes:

- The script follows the [Confluent DuckDB guide](https://docs.confluent.io/cloud/current/topics/tableflow/how-to-guides/query-engines/query-with-duckdb.html): an `ICEBERG` secret with the Tableflow API key and secret as OAuth2 client ID and secret, then `ATTACH 'warehouse'` (the name is only a logical placeholder). That guide covers Confluent Managed Storage; if queries fail with a `403` on `gs://`, configure a DuckDB [GCS secret](https://duckdb.org/docs/stable/core_extensions/httpfs/s3api#gcs-support) with HMAC keys for a service account that has `roles/storage.objectViewer` on the bucket.
- The DuckDB Iceberg extension is experimental. If a query fails with `HTTP 401` after about half an hour, restart DuckDB so the secret is recreated and the catalog re-attached.
- Allow a few minutes after the connector starts for the first snapshot to be published.

### Clean up

```shell
terraform destroy
gcloud storage rm --recursive "gs://$BUCKET_NAME"   # the bucket is not managed by Terraform
```
