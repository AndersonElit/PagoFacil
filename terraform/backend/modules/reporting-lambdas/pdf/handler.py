"""Lambda de formato PDF (DR-6).

Disparada por una rule de EventBridge (detail.format = PDF). Lee el parquet
`processedParquetUri` y escribe el archivo en `output/pdf/<reportType>/<reportId>.pdf`.
"""
import json
import os
import io

import boto3
import pyarrow.parquet as pq
import pyarrow.dataset as ds

REPORT_BUCKET = os.environ.get("REPORT_BUCKET", "pagofacil-reports")
_endpoint = os.environ.get("AWS_ENDPOINT_URL") or None
s3 = boto3.client("s3", endpoint_url=_endpoint)


def _read_table(uri: str):
    """Lee un parquet (prefijo S3) como tabla pyarrow vía s3fs/pyarrow dataset."""
    dataset = ds.dataset(uri, format="parquet", filesystem=_s3_filesystem())
    return dataset.to_table()


def _s3_filesystem():
    import pyarrow.fs as pafs
    return pafs.S3FileSystem(endpoint_override=_endpoint, scheme="http" if _endpoint else "https")


def _detail(event):
    return event.get("detail", event)


def _output_key(report_type: str, report_id: str) -> str:
    return f"output/pdf/{report_type}/{report_id}.pdf"


def handler(event, _context=None):
    from reportlab.lib.pagesizes import A4
    from reportlab.platypus import SimpleDocTemplate, Table, TableStyle
    from reportlab.lib import colors

    d = _detail(event)
    report_id = d["reportId"]
    report_type = d.get("reportType", "report")
    table = _read_table(d["processedParquetUri"])

    data = [table.column_names]
    for row in zip(*[col.to_pylist() for col in table.columns]):
        data.append([str(c) for c in row])

    buf = io.BytesIO()
    doc = SimpleDocTemplate(buf, pagesize=A4)
    t = Table(data)
    t.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
    ]))
    doc.build([t])

    key = _output_key(report_type, report_id)
    s3.put_object(Bucket=REPORT_BUCKET, Key=key, Body=buf.getvalue())
    return {"output": f"s3://{REPORT_BUCKET}/{key}", "rows": table.num_rows}
