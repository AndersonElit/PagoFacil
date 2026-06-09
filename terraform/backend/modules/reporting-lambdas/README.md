# reporting-lambdas — capa serverless de formatos

Generado por `report_lambdas_scaffold.py` (PLAN-reporteria-spark-etl.md §7.2).

```
terraform/backend/modules/reporting-lambdas/
├── variables.tf
├── iam.tf
├── eventbridge.tf
├── formats.tf
├── outputs.tf
├── kafka-consumer/   # consume report.processed -> PutEvents EventBridge (DR-5)
├── pdf/             # parquet -> PDF -> output/pdf/
├── xls/             # parquet -> XLS -> output/xls/
├── csv/             # parquet -> CSV -> output/csv/

```

## Desplegar (dev, floci)

Descomentar el bloque `module "reporting_lambdas"` en
`terraform/backend/environments/dev/main.tf`, luego:

```bash
cd terraform/backend/environments/dev
terraform init
terraform apply
```

El **mismo** módulo aplica en staging/prod (AWS real): solo cambian las variables
`aws_endpoint_url` (vacío => AWS real) pasadas desde cada environment (DR-8).
