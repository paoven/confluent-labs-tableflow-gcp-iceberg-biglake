-- Usage (after `terraform apply`):
--   export TABLEFLOW_API_KEY=<app-reader tableflow api key>
--   export TABLEFLOW_API_SECRET=<app-reader tableflow api secret>
--   export TABLEFLOW_REST_CATALOG_ENDPOINT=<REST Catalog Endpoint>
--   duckdb -ui -init duckdb-setup.sql
-- Keys/secret/endpoint come from: terraform output resource-ids
-- Based on https://docs.confluent.io/cloud/current/topics/tableflow/how-to-guides/query-engines/query-with-duckdb.html
INSTALL httpfs;  LOAD httpfs;
INSTALL iceberg; LOAD iceberg;

CREATE OR REPLACE SECRET iceberg_secret (
    TYPE ICEBERG,
    CLIENT_ID     getenv('TABLEFLOW_API_KEY'),
    CLIENT_SECRET getenv('TABLEFLOW_API_SECRET'),
    ENDPOINT      getenv('TABLEFLOW_REST_CATALOG_ENDPOINT'),
    OAUTH2_SCOPE  'catalog'
);

ATTACH 'warehouse' AS iceberg_catalog (
    TYPE iceberg,
    SECRET iceberg_secret,
    ENDPOINT getenv('TABLEFLOW_REST_CATALOG_ENDPOINT')
);

-- Then: SHOW ALL TABLES;  SELECT * FROM iceberg_catalog."<cluster-id>"."stock-trades" LIMIT 10;
