# Etapa 6 — Capa Serverless de Reportería (Lambdas + EventBridge)

**Proyecto:** PagoFacil — Billetera Digital
**Bounded Context:** BC-07 Reporting — Generación de Formatos
**Stack:** Python 3.12, Terraform, floci (dev), AWS Lambda + EventBridge (staging/prod)
**Scaffolding:** `.claude/templates/report_lambdas_scaffold.py --org pagofacil --formats pdf,xls,csv`

---

## 1. Objetivo

Generar los archivos finales de reporte (PDF, XLS, CSV) en S3 a partir de los Parquet `processed/` producidos por MS2. El desacople via EventBridge permite añadir nuevos formatos sin modificar el pipeline ETL. En dev se usa floci (`VPS_IP:4566`) como emulador de S3, Lambda y EventBridge.

---

## 2. Prerrequisitos

- [ ] Etapas 3h (MS1) y 3i (MS2) funcionales; eventos `report.processed` publicados en Kafka.
- [ ] S3/floci activo en `VPS_IP:4566` con bucket `pagofacil-reports` y paths `processed/` y `output/`.
- [ ] Kafka activo en `VPS_IP:29092`.
- [ ] floci configurado con soporte para Lambda y EventBridge (`VPS_IP:4566`).
- [ ] Secret `pagofacil/dev/reporting-lambdas` en floci.

---

## 3. Scaffolding

El scaffold genera la estructura completa automáticamente:

```bash
# Invocado por scaffold-all-services.sh vía --report-formats pdf,xls,csv
.claude/templates/report_lambdas_scaffold.py \
  --org pagofacil \
  --formats pdf,xls,csv
```

**Árbol de directorios generado:**

```
reporting-lambdas/
├── lambda-kafka-consumer/
│   ├── handler.py               # consume report.processed → PutEvents EventBridge
│   ├── requirements.txt         # confluent-kafka, boto3
│   └── tests/
│       └── test_lambda_consumer.py
├── lambda-pdf-formatter/
│   ├── handler.py               # parquet → PDF via ReportLab/WeasyPrint
│   ├── requirements.txt         # boto3, pandas, pyarrow, reportlab
│   └── tests/
│       └── test_pdf_formatter.py
├── lambda-xls-formatter/
│   ├── handler.py               # parquet → XLS via openpyxl
│   ├── requirements.txt         # boto3, pandas, pyarrow, openpyxl
│   └── tests/
│       └── test_xls_formatter.py
├── lambda-csv-formatter/
│   ├── handler.py               # parquet → CSV via pandas
│   ├── requirements.txt         # boto3, pandas, pyarrow
│   └── tests/
│       └── test_csv_formatter.py
└── terraform/
    ├── main.tf                  # bus EventBridge + invocación
    ├── lambdas.tf               # aws_lambda_function por formato
    ├── iam.tf                   # roles S3 + EventBridge
    ├── variables.tf
    └── outputs.tf
```

---

## 4. Lambda Kafka Consumer

**Responsabilidad:** Consume el tópico `report.processed` y publica un evento a EventBridge con el formato de salida solicitado.

```python
# lambda-kafka-consumer/handler.py
def handler(event, context):
    for record in event["records"]["report.processed"]:
        payload = json.loads(base64.b64decode(record["value"]))
        
        eb_event = {
            "Source": "pagofacil.reporting",
            "DetailType": "ReportProcessed",
            "Detail": json.dumps({
                "execution_id": payload["execution_id"],
                "report_type": payload["report_type"],
                "format": payload["output_format"],        # PDF | XLS | CSV
                "parquet_processed_path": payload["parquet_processed_path"],
                "tenant_id": payload["tenant_id"]
            }),
            "EventBusName": "pagofacil-reporting"
        }
        
        boto3.client("events", endpoint_url=os.getenv("AWS_ENDPOINT_URL")).put_events(
            Entries=[eb_event]
        )
```

---

## 5. EventBridge — Reglas de Enrutamiento

Bus: `pagofacil-reporting`

| Regla | Event Pattern | Target Lambda |
|---|---|---|
| `report-pdf-rule` | `{"detail": {"format": ["PDF"]}}` | `pagofacil-lambda-pdf-formatter` |
| `report-xls-rule` | `{"detail": {"format": ["XLS"]}}` | `pagofacil-lambda-xls-formatter` |
| `report-csv-rule` | `{"detail": {"format": ["CSV"]}}` | `pagofacil-lambda-csv-formatter` |

Cada regla activa **únicamente** la lambda del formato correspondiente. Añadir un nuevo formato = añadir una nueva lambda + una nueva regla sin modificar las existentes.

---

## 6. Lambdas de Formato

### Lambda PDF (`lambda-pdf-formatter`)

```python
def handler(event, context):
    detail = event["detail"]
    parquet_path = detail["parquet_processed_path"]
    execution_id = detail["execution_id"]
    
    # Lee Parquet desde S3/floci
    df = pd.read_parquet(f"s3://{parquet_path}", storage_options={"endpoint_url": AWS_ENDPOINT_URL})
    
    # Genera PDF con ReportLab
    pdf_bytes = generate_pdf(df, report_type=detail["report_type"])
    
    # Escribe en S3 output/
    output_path = f"pagofacil-reports/output/{detail['report_type']}/{execution_id}/report.pdf"
    s3.put_object(Bucket="pagofacil-reports", Key=output_path, Body=pdf_bytes)
    
    # Actualiza report_executions → COMPLETED
    update_execution_status(execution_id, "COMPLETED", output_path)
```

### Lambda XLS (`lambda-xls-formatter`)

Igual que PDF pero usa `openpyxl` para generar `.xlsx`. Nombre de archivo: `report.xlsx`.

### Lambda CSV (`lambda-csv-formatter`)

Usa `pandas.to_csv()`. Nombre de archivo: `report.csv`. Incluye cabeceras.

Todos los archivos se escriben en: `s3://pagofacil-reports/output/{report_type}/{execution_id}/{format}/report.{ext}`

---

## 7. Terraform

### Dev (floci `VPS_IP:4566`)

```hcl
# reporting-lambdas/terraform/variables.tf
variable "aws_endpoint_url" {
  default = "http://<VPS_IP>:4566"
}

variable "enable_reporting_serverless" {
  default = true
}
```

```hcl
# reporting-lambdas/terraform/main.tf
resource "aws_cloudwatch_event_bus" "reporting" {
  count = var.enable_reporting_serverless ? 1 : 0
  name  = "pagofacil-reporting"
}

resource "aws_cloudwatch_event_rule" "pdf" {
  count         = var.enable_reporting_serverless ? 1 : 0
  event_bus_name = aws_cloudwatch_event_bus.reporting[0].name
  event_pattern = jsonencode({ detail = { format = ["PDF"] } })
}
```

Para staging/prod: quitar `endpoint_url` override; usar AWS real.

### Estructura completa del módulo Terraform

```
terraform/
├── main.tf         # EventBus + Rules + Targets
├── lambdas.tf      # aws_lambda_function por formato (zip deployments)
├── iam.tf          # aws_iam_role + policies (S3 read/write + EventBridge PutEvents)
├── variables.tf    # aws_endpoint_url, enable_reporting_serverless, env
└── outputs.tf      # lambda ARNs, event_bus ARN
```

**Ejecución en dev:**

```bash
cd reporting-lambdas/terraform
terraform init -backend-config="endpoint=http://<VPS_IP>:4566"
terraform apply -var="aws_endpoint_url=http://<VPS_IP>:4566" -auto-approve
```

---

## 8. Especificación TDD (pytest)

> **Regla:** prueba FALLA (Red) antes del código de producción (Green). Seguido de Refactor.

### Lambda Consumer

| Archivo de test | Caso | Elemento que precede |
|---|---|---|
| `test_lambda_consumer.py` | `test_should_put_event_for_pdf_format` | `handler()` — PutEvents con `detail.format = "PDF"` | Lambda Consumer `handler.py` |
| `test_lambda_consumer.py` | `test_should_put_event_for_each_supported_format` | PutEvents por cada formato recibido | `handler.py` |
| `test_lambda_consumer.py` | `test_should_use_correct_event_bus_name` | Bus name `pagofacil-reporting` | `handler.py` |

### Lambda PDF

| Archivo de test | Caso | Elemento que precede |
|---|---|---|
| `test_pdf_formatter.py` | `test_should_generate_valid_pdf_from_parquet` | parquet fixture → archivo PDF ≥ 1 KB | `handler.py` PDF formatter |
| `test_pdf_formatter.py` | `test_should_write_pdf_to_correct_s3_path` | Ruta `output/{type}/{id}/report.pdf` | `handler.py` |
| `test_pdf_formatter.py` | `test_should_update_execution_status_to_completed` | `report_executions` actualizado | `handler.py` |

### Lambda XLS

| Archivo de test | Caso | Elemento que precede |
|---|---|---|
| `test_xls_formatter.py` | `test_should_generate_xls_with_correct_sheet` | parquet → .xlsx con hoja del tipo de reporte | XLS `handler.py` |
| `test_xls_formatter.py` | `test_should_include_all_expected_columns` | Columnas del DataFrame en el XLS | XLS `handler.py` |

### Lambda CSV

| Archivo de test | Caso | Elemento que precede |
|---|---|---|
| `test_csv_formatter.py` | `test_should_generate_csv_with_headers` | parquet → CSV con cabecera | CSV `handler.py` |
| `test_csv_formatter.py` | `test_should_write_csv_to_correct_s3_path` | Ruta `output/{type}/{id}/report.csv` | CSV `handler.py` |

### Enrutamiento EventBridge

| Archivo de test | Caso | Elemento que precede |
|---|---|---|
| `test_eventbridge_routing.py` | `test_pdf_rule_activates_only_pdf_lambda` | `detail.format = "PDF"` → solo rule PDF activa | Reglas EventBridge |
| `test_eventbridge_routing.py` | `test_xls_rule_activates_only_xls_lambda` | `detail.format = "XLS"` → solo rule XLS | Reglas EventBridge |

**Umbral de cobertura:** ≥ 80% en todas las lambdas.

---

## 9. Integración con el Pipeline ETL

```
MS2 publica report.processed (Kafka)
  → Lambda Kafka Consumer
  → EventBridge PutEvents
  → Rule (by detail.format)
  → Lambda Formatter (PDF | XLS | CSV)
  → Escribe archivo en S3 output/
  → Actualiza report_executions.status = COMPLETED
  → Frontend (polling useExecutionStatus) detecta COMPLETED
  → DownloadButton habilitado
```

---

## 10. Criterios de Aceptación

- [ ] `ENABLE_REPORTING_SERVERLESS=true` y `terraform apply` en floci completan sin errores.
- [ ] Lambda Consumer recibe evento `report.processed` desde Kafka y publica a EventBridge bus `pagofacil-reporting`.
- [ ] Regla `report-pdf-rule` activa únicamente la lambda PDF (XLS y CSV no son invocadas).
- [ ] Lambda PDF genera un archivo PDF válido en S3 `output/{type}/{executionId}/report.pdf`.
- [ ] Lambda XLS genera un archivo `.xlsx` con hojas y columnas correctas.
- [ ] Lambda CSV genera un archivo `.csv` con cabecera.
- [ ] `pagofacil_reporting.report_executions.status` es actualizado a `COMPLETED` con `output_path` correcto.
- [ ] Frontend `useExecutionStatus` detecta `COMPLETED` y habilita `DownloadButton`.
- [ ] `pytest` verde en todas las lambdas; cobertura ≥ 80%.
- [ ] Añadir nuevo formato (ej. JSON) = añadir nueva lambda + nueva regla EventBridge; sin modificar lambdas existentes.
