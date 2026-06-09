#!/usr/bin/env bash
# Crea (o actualiza) el secret de desarrollo en floci (VPS).
# Requiere que floci esté corriendo en $VPS_IP:4566 (o localhost:4566 por defecto).
# Uso: VPS_IP=192.168.122.50 bash create-secrets-dev.sh

SECRET_NAME="pagofacil/dev/identity-service"
ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4566}"
REGION="us-east-1"

if aws --endpoint-url="$ENDPOINT" secretsmanager describe-secret \
       --secret-id "$SECRET_NAME" --region "$REGION" &>/dev/null; then
    aws --endpoint-url="$ENDPOINT" secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" \
        --secret-string '{"SERVER_PORT": "8081", "R2DBC_URL": "r2dbc:postgresql://${VPS_IP:-localhost}:5432/pagofacil_identity_service", "DB_USERNAME": "pagofacil", "DB_PASSWORD": "change_me", "KAFKA_BOOTSTRAP_SERVERS": "${VPS_IP:-localhost}:29092"}' \
        --region "$REGION"
    echo "Secret actualizado: $SECRET_NAME"
else
    aws --endpoint-url="$ENDPOINT" secretsmanager create-secret \
        --name "$SECRET_NAME" \
        --secret-string '{"SERVER_PORT": "8081", "R2DBC_URL": "r2dbc:postgresql://${VPS_IP:-localhost}:5432/pagofacil_identity_service", "DB_USERNAME": "pagofacil", "DB_PASSWORD": "change_me", "KAFKA_BOOTSTRAP_SERVERS": "${VPS_IP:-localhost}:29092"}' \
        --region "$REGION"
    echo "Secret creado: $SECRET_NAME"
fi
