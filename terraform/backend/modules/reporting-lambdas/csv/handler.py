"""Lambda de formato CSV (DR-6).

Disparada por una rule de EventBridge (detail.format = CSV). Lee el parquet
`processedParquetUri` y escribe el archivo en `output/csv/<reportType>/<reportId>.csv`.
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
    return f"output/csv/{report_type}/{report_id}.csv"


def handler(event, _context=None):
    d = _detail(event)
    report_id = d["reportId"]
    report_type = d.get("reportType", "report")
    table = _read_table(d["processedParquetUri"])

    import csv
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(table.column_names)
    for row in zip(*[col.to_pylist() for col in table.columns]):
        writer.writerow(row)

    key = _output_key(report_type, report_id)
    s3.put_object(Bucket=REPORT_BUCKET, Key=key, Body=buf.getvalue().encode("utf-8"))
    return {"output": f"s3://{REPORT_BUCKET}/{key}", "rows": table.num_rows}
