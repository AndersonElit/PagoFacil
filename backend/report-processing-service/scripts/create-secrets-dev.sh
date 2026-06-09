#!/usr/bin/env bash
# Crea (o actualiza) el secret de desarrollo en floci (emulador AWS).
# Requiere que floci esté corriendo en http://localhost:4566.

SECRET_NAME="pagofacil/dev/report-processing-service"
ENDPOINT="http://localhost:4566"
REGION="us-east-1"

if aws --endpoint-url="$ENDPOINT" secretsmanager describe-secret \
       --secret-id "$SECRET_NAME" --region "$REGION" &>/dev/null; then
    aws --endpoint-url="$ENDPOINT" secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string '{"AWS_ENDPOINT_URL": "http://localhost:4566", "AWS_ACCESS_KEY_ID": "test", "AWS_SECRET_ACCESS_KEY": "test", "AWS_REGION": "us-east-1", "REPORT_BUCKET": "reports", "KAFKA_BOOTSTRAP_SERVERS": "localhost:9092"}' \
        --region "$REGION"
    echo "Secret actualizado: $SECRET_NAME"
else
    aws --endpoint-url="$ENDPOINT" secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --secret-string '{"AWS_ENDPOINT_URL": "http://localhost:4566", "AWS_ACCESS_KEY_ID": "test", "AWS_SECRET_ACCESS_KEY": "test", "AWS_REGION": "us-east-1", "REPORT_BUCKET": "reports", "KAFKA_BOOTSTRAP_SERVERS": "localhost:9092"}' \
        --region "$REGION"
    echo "Secret creado: $SECRET_NAME"
fi
