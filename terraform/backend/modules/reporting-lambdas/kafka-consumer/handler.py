"""Lambda Kafka Consumer (DR-5).

Consume `report.processed` (trigger Kafka/MSK o poller) y traduce cada evento a EventBridge
(PutEvents), emitiendo un evento `ReportFormatRequested` por cada formato solicitado.
NO genera formatos: solo enruta (DR-5).
"""
import json
import os
import base64

import boto3

EVENT_BUS = os.environ.get("EVENTBRIDGE_BUS", "pagofacil-report-bus")
SOURCE = "pagofacil.reporting"
DEFAULT_FORMATS = ["PDF", "XLS", "CSV"]

_endpoint = os.environ.get("AWS_ENDPOINT_URL") or None
events = boto3.client("events", endpoint_url=_endpoint)


def _records(event):
    """Soporta el envelope de trigger MSK/Kafka (event['records']) y la invocación directa."""
    if "records" in event:
        for _topic, msgs in event["records"].items():
            for m in msgs:
                raw = m.get("value", "")
                try:
                    yield json.loads(base64.b64decode(raw).decode("utf-8"))
                except Exception:
                    yield json.loads(raw)
    else:
        yield event


def handler(event, _context=None):
    entries = []
    for msg in _records(event):
        formats = msg.get("formats") or DEFAULT_FORMATS
        for fmt in formats:
            detail = {
                "reportId": msg.get("reportId"),
                "reportType": msg.get("reportType"),
                "processedParquetUri": msg.get("processedParquetUri"),
                "format": fmt.upper(),
            }
            entries.append({
                "Source": SOURCE,
                "DetailType": "ReportFormatRequested",
                "Detail": json.dumps(detail),
                "EventBusName": EVENT_BUS,
            })
    if entries:
        events.put_events(Entries=entries)
    return {"published": len(entries)}
