# Etapa 6 — Reportería Serverless (Lambda + EventBridge)

**Proyecto:** PagoFacil | **Tipo:** Lambdas Python + EventBridge | **Ambiente:** dev (floci)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo

Implementar la capa final del pipeline de reportería: las lambdas que convierten el Parquet procesado por MS2 en archivos descargables (PDF, XLS, CSV) y los depositan en S3 `pagofacil-reports/`. La arquitectura usa EventBridge como bus de enrutamiento entre MS2 y las lambdas de formato.

**Flujo completo:**

```
MS2 publica report.processed (Kafka)
    → Lambda Kafka Consumer (Python) lee el evento
    → Publica a EventBridge (pagofacil-report-bus) con detail-type por formato solicitado
    → EventBridge enruta:
        - rule pdf-rule → lambda-pdf
        - rule xls-rule → lambda-xls
        - rule csv-rule → lambda-csv
    → Cada lambda lee Parquet processed/ de S3 → genera archivo → deposita en S3 pagofacil-reports/
    → audit-service actualiza report_jobs.status = COMPLETADO con s3_key_output
```

---

## 2. Prerrequisitos

- Etapa 3i completa (MS2 publicando `report.processed`).
- Bucket S3 `pagofacil-reports` en floci.
- Bucket S3 `pagofacil-parquet-processed` con Parquet de prueba disponible.
- Terraform con módulo `reporting-serverless` aplicado en dev (floci).

---

## 3. Scaffolding

```bash
python3 .claude/templates/report_lambdas_scaffold.py \
  --org pagofacil \
  --formats pdf,xls,csv
```

**Estructura generada:**

```
reporting-lambdas/
├── lambda_kafka_consumer/
│   ├── handler.py
│   ├── requirements.txt
│   └── tests/
│       └── test_handler.py
├── lambda_pdf/
│   ├── handler.py
│   ├── requirements.txt
│   └── tests/
│       └── test_handler.py
├── lambda_xls/
│   ├── handler.py
│   ├── requirements.txt
│   └── tests/
│       └── test_handler.py
├── lambda_csv/
│   ├── handler.py
│   ├── requirements.txt
│   └── tests/
│       └── test_handler.py
└── terraform/
    ├── main.tf          # EventBridge bus + 3 rules + 4 lambdas
    ├── variables.tf
    └── outputs.tf
```

---

## 4. Lambda Kafka Consumer

**Propósito:** Consumir `report.processed` de Kafka y publicar el evento a EventBridge con `detail-type` apropiado por formato solicitado.

```python
# lambda_kafka_consumer/handler.py

def handler(event, context):
    """Trigger: Kafka topic report.processed (MSK trigger en staging/prod; manual en dev)"""
    for record in event['records']['report.processed']:
        payload = json.loads(base64.b64decode(record['value']))
        job_id = payload['jobId']
        formats = payload['formats']  # ["PDF", "XLS", "CSV"]
        s3_key_processed = payload['s3KeyProcessed']
        
        for fmt in formats:
            eventbridge.put_events(Entries=[{
                'EventBusName': 'pagofacil-report-bus',
                'Source': 'pagofacil.reporting',
                'DetailType': f'ReportProcessed.{fmt}',
                'Detail': json.dumps({
                    'jobId': job_id,
                    'format': fmt,
                    's3KeyProcessed': s3_key_processed
                })
            }])
```

---

## 5. Lambdas de Formato

### lambda-pdf

```python
# lambda_pdf/handler.py
import pandas as pd
from reportlab.lib.pagesizes import A4
from reportlab.platypus import SimpleDocTemplate, Table

def handler(event, context):
    detail = event['detail']
    df = pd.read_parquet(f"s3://pagofacil-parquet-processed/{detail['s3KeyProcessed']}")
    pdf_key = f"reports/{detail['jobId']}/report.pdf"
    # ... generar PDF con ReportLab
    s3.upload_fileobj(pdf_buffer, 'pagofacil-reports', pdf_key)
    # ... notificar audit-service vía Kafka o API que el reporte está listo
    return {'statusCode': 200, 's3Key': pdf_key}
```

### lambda-xls

```python
# lambda_xls/handler.py
import pandas as pd

def handler(event, context):
    detail = event['detail']
    df = pd.read_parquet(f"s3://pagofacil-parquet-processed/{detail['s3KeyProcessed']}")
    xls_key = f"reports/{detail['jobId']}/report.xlsx"
    # ... generar XLS con openpyxl (via pandas)
    df.to_excel(xls_buffer, index=False, engine='openpyxl')
    s3.upload_fileobj(xls_buffer, 'pagofacil-reports', xls_key)
    return {'statusCode': 200, 's3Key': xls_key}
```

### lambda-csv

```python
# lambda_csv/handler.py
import pandas as pd

def handler(event, context):
    detail = event['detail']
    df = pd.read_parquet(f"s3://pagofacil-parquet-processed/{detail['s3KeyProcessed']}")
    csv_key = f"reports/{detail['jobId']}/report.csv"
    df.to_csv(csv_buffer, index=False)
    s3.upload_fileobj(csv_buffer, 'pagofacil-reports', csv_key)
    return {'statusCode': 200, 's3Key': csv_key}
```

---

## 6. Terraform (EventBridge)

```hcl
# terraform/main.tf (simplificado)

resource "aws_cloudwatch_event_bus" "report_bus" {
  name = "pagofacil-report-bus"
}

resource "aws_cloudwatch_event_rule" "pdf_rule" {
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  event_pattern = jsonencode({
    "source": ["pagofacil.reporting"],
    "detail-type": ["ReportProcessed.PDF"]
  })
}

resource "aws_cloudwatch_event_target" "pdf_target" {
  rule           = aws_cloudwatch_event_rule.pdf_rule.name
  event_bus_name = aws_cloudwatch_event_bus.report_bus.name
  arn            = aws_lambda_function.lambda_pdf.arn
}
# (repetir para xls_rule y csv_rule)
```

**Aplicar en dev (floci):**

```bash
cd reporting-lambdas/terraform
terraform init -backend-config="endpoint=http://localhost:4566"
terraform apply -auto-approve
```

---

## 7. Especificación TDD — Pruebas (pytest)

> Cada lambda se prueba con pytest contra floci (S3 y EventBridge de LocalStack).

### Lambda Kafka Consumer

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Evento Kafka con 3 formatos → `put_events` llamado 3 veces | 3 eventos publicados a EventBridge (uno por formato) |
| `test_handler.py` | EventBridge rechaza evento (error 400) | Lambda lanza excepción; error registrado en CloudWatch |
| `test_handler.py` | Evento Kafka con formato desconocido | Lambda loga warning y continúa sin publicar |

### Lambda PDF

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Parquet válido en S3 floci → genera PDF → sube a `pagofacil-reports/` | Archivo PDF válido en S3; `s3Key` en response |
| `test_handler.py` | Parquet no encontrado en S3 | Lambda retorna error 404; no crea archivo |

### Lambda XLS

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Parquet válido → genera XLSX → sube a S3 | Archivo XLSX parseable con openpyxl |
| `test_handler.py` | DataFrame vacío → XLSX con solo headers | Archivo válido con 0 filas de datos |

### Lambda CSV

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_handler.py` | Parquet válido → CSV con separador coma → sube a S3 | CSV parseable con pandas |
| `test_handler.py` | Verificar encoding UTF-8 en CSV | Caracteres especiales correctamente codificados |

### Enrutamiento EventBridge

| Archivo de test | Escenario | Resultado esperado |
|---|---|---|
| `test_eventbridge_routing.py` | Evento `detail-type: ReportProcessed.PDF` → activa `pdf_rule` | Solo `lambda-pdf` invocada |
| `test_eventbridge_routing.py` | Evento `detail-type: ReportProcessed.XLS` → activa `xls_rule` | Solo `lambda-xls` invocada |
| `test_eventbridge_routing.py` | Evento `detail-type: ReportProcessed.CSV` → activa `csv_rule` | Solo `lambda-csv` invocada |

---

## 8. Criterios de Aceptación

- [ ] Cada lambda tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `pytest reporting-lambdas/` pasa en verde.
- [ ] Terraform apply en dev crea el bus `pagofacil-report-bus` y las 3 rules en floci EventBridge.
- [ ] El enrutamiento de EventBridge activa la lambda correcta según `detail-type`.
- [ ] Lambda-pdf genera PDF válido y lo deposita en `pagofacil-reports/<jobId>/report.pdf`.
- [ ] Lambda-xls genera XLSX válido y lo deposita en `pagofacil-reports/<jobId>/report.xlsx`.
- [ ] Lambda-csv genera CSV UTF-8 válido y lo deposita en `pagofacil-reports/<jobId>/report.csv`.
- [ ] Flujo E2E completo: MS2 publica `report.processed` → 3 archivos en S3 `pagofacil-reports/` (verificado en Etapa 5, Sección 4).
- [ ] `audit-service` actualiza `report_jobs.status = COMPLETADO` con las S3 keys de los 3 formatos.
- [ ] `GET /v1/audit/reports/{reportId}/download` retorna URL pre-firmada para el formato solicitado.
