# Etapa 6 — Reportería Serverless (Lambda + EventBridge)

**Proyecto:** PagoFacil | **Tipo:** Lambdas Python + EventBridge | **Ambiente:** dev (floci)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo

Implementar la capa final del pipeline de reportería: las lambdas que convierten el Parquet procesado por MS2 en archivos descargables (PDF, XLS, CSV) y los depositan en S3 `pagofacil-reports/output/<formato>/`. La arquitectura usa EventBridge como bus de enrutamiento entre MS2 y las lambdas de formato.

**Flujo completo:**

```
MS2 publica report.processed (Kafka)
    → Lambda Kafka Consumer (Python) lee el evento
    → Publica a EventBridge (pagofacil-report-bus) un evento ReportFormatRequested por formato
    → EventBridge enruta por detail.format:
        - "PDF" → lambda-pdf
        - "XLS" → lambda-xls
        - "CSV" → lambda-csv
    → Cada lambda lee Parquet de S3 (processedParquetUri)
      → genera archivo → deposita en S3 pagofacil-reports/output/<fmt>/<reportType>/<reportId>.<ext>
    → audit-service actualiza report_jobs.status = COMPLETADO con s3_key_output
```

---

## 2. Prerrequisitos

- Etapa 3i completa (MS2 publicando `report.processed`).
- `base-infrastructure-builder.sh` ejecutado: crea `terraform/backend/modules/reporting-lambdas/`
  y el bloque `module "reporting_lambdas"` comentado en `terraform/backend/environments/dev/main.tf`.
- Bucket S3 `pagofacil-reports` en floci (lo crea `base-infrastructure-builder.sh`).
- Parquet de prueba disponible bajo el prefijo `processed/` del bucket.

---

## 3. Scaffolding

```bash
python3 .claude/templates/report_lambdas_scaffold.py \
  --org pagofacil \
  --formats pdf,xls,csv
```

El script rellena el módulo Terraform que `base-infrastructure-builder.sh` dejó vacío.
**Toda la capa serverless vive dentro del árbol Terraform:**

```
terraform/backend/modules/reporting-lambdas/
├── variables.tf
├── iam.tf
├── eventbridge.tf         # bus + lambda kafka-consumer + trigger MSK
├── formats.tf             # lambdas pdf/xls/csv + rules + permisos
├── outputs.tf
├── README.md
├── kafka-consumer/        # código fuente de la lambda consumidora
│   ├── handler.py
│   └── requirements.txt
├── pdf/                   # código fuente de la lambda PDF
│   ├── handler.py
│   └── requirements.txt
├── xls/                   # código fuente de la lambda XLS
│   ├── handler.py
│   └── requirements.txt
└── csv/                   # código fuente de la lambda CSV
    ├── handler.py
    └── requirements.txt
```

Los ZIPs de despliegue se generan en tiempo de `terraform apply` mediante `archive_file`:

```hcl
data "archive_file" "kafka_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/kafka-consumer"
  output_path = "${path.module}/build/kafka-consumer.zip"
}
```

---

## 4. Lambda Kafka Consumer

**Propósito:** Consumir `report.processed` de Kafka y publicar a EventBridge un evento
`ReportFormatRequested` por cada formato solicitado (DR-5).

```python
# kafka-consumer/handler.py (generado por el scaffold)

EVENT_BUS = os.environ.get("EVENTBRIDGE_BUS", "pagofacil-report-bus")
SOURCE = "pagofacil.reporting"
DEFAULT_FORMATS = ["PDF", "XLS", "CSV"]

def handler(event, _context=None):
    entries = []
    for msg in _records(event):          # soporta envelope MSK y llamada directa
        formats = msg.get("formats") or DEFAULT_FORMATS
        for fmt in formats:
            detail = {
                "reportId":             msg.get("reportId"),
                "reportType":           msg.get("reportType"),
                "processedParquetUri":  msg.get("processedParquetUri"),
                "format":               fmt.upper(),
            }
            entries.append({
                "Source":      SOURCE,
                "DetailType":  "ReportFormatRequested",
                "Detail":      json.dumps(detail),
                "EventBusName": EVENT_BUS,
            })
    if entries:
        events.put_events(Entries=entries)
    return {"published": len(entries)}
```

---

## 5. Lambdas de Formato

Cada lambda recibe el evento de EventBridge, lee el Parquet desde `processedParquetUri`
vía pyarrow y escribe el archivo resultante en `output/<fmt>/<reportType>/<reportId>.<ext>`.

### lambda-pdf

```python
# pdf/handler.py (generado por el scaffold)
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Table, TableStyle
from reportlab.lib import colors

def handler(event, _context=None):
    d = event.get("detail", event)
    table = _read_table(d["processedParquetUri"])   # pyarrow dataset sobre S3
    # construye data[][] con cabeceras y filas
    # genera PDF con ReportLab y sube a S3
    key = f"output/pdf/{d['reportType']}/{d['reportId']}.pdf"
    s3.put_object(Bucket=REPORT_BUCKET, Key=key, Body=buf.getvalue())
    return {"output": f"s3://{REPORT_BUCKET}/{key}", "rows": table.num_rows}
```

### lambda-xls

```python
# xls/handler.py (generado por el scaffold)
from openpyxl import Workbook

def handler(event, _context=None):
    d = event.get("detail", event)
    table = _read_table(d["processedParquetUri"])
    # escribe con openpyxl y sube a S3
    key = f"output/xls/{d['reportType']}/{d['reportId']}.xlsx"
    s3.put_object(Bucket=REPORT_BUCKET, Key=key, Body=buf.getvalue())
    return {"output": f"s3://{REPORT_BUCKET}/{key}", "rows": table.num_rows}
```

### lambda-csv

```python
# csv/handler.py (generado por el scaffold)
import csv

def handler(event, _context=None):
    d = event.get("detail", event)
    table = _read_table(d["processedParquetUri"])
    # escribe con csv.writer (stdlib) y sube a S3
    key = f"output/csv/{d['reportType']}/{d['reportId']}.csv"
    s3.put_object(Bucket=REPORT_BUCKET, Key=key, Body=buf.getvalue().encode("utf-8"))
    return {"output": f"s3://{REPORT_BUCKET}/{key}", "rows": table.num_rows}
```

---

## 6. Terraform

El scaffold rellena `terraform/backend/modules/reporting-lambdas/` con cuatro archivos `.tf`.
La estructura clave generada:

```hcl
# eventbridge.tf — bus + kafka consumer + trigger MSK
resource "aws_cloudwatch_event_bus" "report_bus" {
  name = "${var.org}-report-bus"
}

data "archive_file" "kafka_consumer" {
  type        = "zip"
  source_dir  = "${path.module}/kafka-consumer"   # código dentro del módulo
  output_path = "${path.module}/build/kafka-consumer.zip"
}

resource "aws_lambda_function" "kafka_consumer" { ... }

resource "aws_lambda_event_source_mapping" "kafka_consumer" {
  topics            = [var.kafka_topic]
  starting_position = "TRIM_HORIZON"
  self_managed_event_source {
    endpoints = { KAFKA_BOOTSTRAP_SERVERS = var.kafka_bootstrap_servers }
  }
}

# formats.tf — una lambda + rule + permission por formato (pdf/xls/csv)
data "archive_file" "pdf" {
  source_dir  = "${path.module}/pdf"              # código dentro del módulo
  output_path = "${path.module}/build/pdf.zip"
}

resource "aws_cloudwatch_event_rule" "pdf" {
  event_pattern = jsonencode({
    "source"      = ["pagofacil.reporting"]
    "detail-type" = ["ReportFormatRequested"]
    "detail"      = { "format" = ["PDF"] }
  })
}
```

**Activar el módulo y aplicar en dev (floci):**

```bash
# 1. Ejecutar el scaffold (rellena terraform/backend/modules/reporting-lambdas/)
python3 .claude/templates/report_lambdas_scaffold.py --org pagofacil --formats pdf,xls,csv

# 2. Descomentar el bloque en terraform/backend/environments/dev/main.tf:
# module "reporting_lambdas" {
#   source                  = "../../modules/reporting-lambdas"
#   org                     = local.project_name
#   kafka_topic             = "report.processed"
#   kafka_bootstrap_servers = local.kafka_bootstrap_brokers
#   lambda_runtime          = "python3.12"
#   report_bucket           = "${local.project_name}-reports"
#   aws_endpoint_url        = "http://localhost:4566"
# }

# 3. Aplicar
cd terraform/backend/environments/dev
terraform init
terraform apply
```

El mismo módulo aplica en staging/prod (AWS real): solo cambia `aws_endpoint_url` (vacío ⇒ AWS real).

---

## 7. Especificación TDD — Pruebas (pytest)

> Cada lambda se prueba con pytest contra floci (S3 y EventBridge de LocalStack).

### Lambda Kafka Consumer

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Evento Kafka con 3 formatos → `put_events` llamado 1 vez con 3 entries | 3 eventos publicados a EventBridge (uno por formato) |
| `test_handler.py` | Evento sin campo `formats` → usa DEFAULT_FORMATS | 3 eventos publicados (pdf, xls, csv) |
| `test_handler.py` | Invocación directa (sin envelope MSK) | Lambda procesa el payload directamente |

### Lambda PDF

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Parquet válido en S3 floci → genera PDF → sube a `pagofacil-reports/output/pdf/` | Archivo PDF válido en S3; `output` en response |
| `test_handler.py` | Parquet no encontrado en S3 | Lambda lanza excepción |

### Lambda XLS

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Parquet válido → genera XLSX → sube a S3 | Archivo XLSX parseable con openpyxl |
| `test_handler.py` | DataFrame vacío → XLSX con solo headers | Archivo válido con 0 filas de datos |

### Lambda CSV

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Parquet válido → CSV con separador coma → sube a S3 | CSV parseable |
| `test_handler.py` | Verificar encoding UTF-8 en CSV | Caracteres especiales correctamente codificados |

### Enrutamiento EventBridge

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_eventbridge_routing.py` | Evento con `detail.format = "PDF"` → activa rule pdf | Solo `lambda-pdf` invocada |
| `test_eventbridge_routing.py` | Evento con `detail.format = "XLS"` → activa rule xls | Solo `lambda-xls` invocada |
| `test_eventbridge_routing.py` | Evento con `detail.format = "CSV"` → activa rule csv | Solo `lambda-csv` invocada |

---

## 8. Criterios de Aceptación

- [ ] `report_lambdas_scaffold.py` ejecutado: `terraform/backend/modules/reporting-lambdas/` poblado con `.tf` y código fuente de lambdas.
- [ ] Bloque `module "reporting_lambdas"` descomentado en `terraform/backend/environments/dev/main.tf`.
- [ ] `terraform apply` en dev crea el bus `pagofacil-report-bus`, 4 lambdas y 3 rules en floci EventBridge.
- [ ] Cada lambda tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] El enrutamiento de EventBridge activa la lambda correcta según `detail.format`.
- [ ] Lambda-pdf genera PDF válido en `pagofacil-reports/output/pdf/<reportType>/<reportId>.pdf`.
- [ ] Lambda-xls genera XLSX válido en `pagofacil-reports/output/xls/<reportType>/<reportId>.xlsx`.
- [ ] Lambda-csv genera CSV UTF-8 válido en `pagofacil-reports/output/csv/<reportType>/<reportId>.csv`.
- [ ] Flujo E2E completo: MS2 publica `report.processed` → 3 archivos en S3 `pagofacil-reports/output/`.
- [ ] `audit-service` actualiza `report_jobs.status = COMPLETADO` con las S3 keys de los 3 formatos.
- [ ] `GET /v1/audit/reports/{reportId}/download` retorna URL pre-firmada para el formato solicitado.
