#!/usr/bin/env bash
# Crea (o actualiza) el secret de desarrollo del integration-service en floci (VPS).
# Uso: VPS_IP=192.168.122.50 bash create-secrets-dev.sh
SECRET_NAME="pagofacil/dev/integration-service"
ENDPOINT="${FLOCI_ENDPOINT:-http://localhost:4566}"
REGION="us-east-1"

if aws --endpoint-url="$ENDPOINT" secretsmanager describe-secret \
       --secret-id "$SECRET_NAME" --region "$REGION" &>/dev/null; then
    aws --endpoint-url="$ENDPOINT" secretsmanager put-secret-value \
        --secret-id "$SECRET_NAME" --secret-string '{"SERVER_PORT": "8090", "R2DBC_URL": "r2dbc:postgresql://${VPS_IP:-localhost}:5432/mydb", "DB_USERNAME": "postgres", "DB_PASSWORD": "change_me", "KAFKA_BOOTSTRAP_SERVERS": "${VPS_IP:-localhost}:29092", "KAFKA_CONSUMER_GROUP_ID": "integration-service-group", "LRA_COORDINATOR_URL": "http://${VPS_IP:-localhost}:50000/lra-coordinator", "EXT_KYC_BASE_URL": "http://${VPS_IP:-localhost}:9999/kyc", "EXT_AML_BASE_URL": "http://${VPS_IP:-localhost}:9999/aml", "EXT_FINANCIAL_ENTITIES_BASE_URL": "http://${VPS_IP:-localhost}:9999/financial-entities", "EXT_PAYMENT_GATEWAYS_BASE_URL": "http://${VPS_IP:-localhost}:9999/payment-gateways", "EXT_SMS_EMAIL_BASE_URL": "http://${VPS_IP:-localhost}:9999/sms-email"}' --region "$REGION"
    echo "Secret actualizado: $SECRET_NAME"
else
    aws --endpoint-url="$ENDPOINT" secretsmanager create-secret \
        --name "$SECRET_NAME" --secret-string '{"SERVER_PORT": "8090", "R2DBC_URL": "r2dbc:postgresql://${VPS_IP:-localhost}:5432/mydb", "DB_USERNAME": "postgres", "DB_PASSWORD": "change_me", "KAFKA_BOOTSTRAP_SERVERS": "${VPS_IP:-localhost}:29092", "KAFKA_CONSUMER_GROUP_ID": "integration-service-group", "LRA_COORDINATOR_URL": "http://${VPS_IP:-localhost}:50000/lra-coordinator", "EXT_KYC_BASE_URL": "http://${VPS_IP:-localhost}:9999/kyc", "EXT_AML_BASE_URL": "http://${VPS_IP:-localhost}:9999/aml", "EXT_FINANCIAL_ENTITIES_BASE_URL": "http://${VPS_IP:-localhost}:9999/financial-entities", "EXT_PAYMENT_GATEWAYS_BASE_URL": "http://${VPS_IP:-localhost}:9999/payment-gateways", "EXT_SMS_EMAIL_BASE_URL": "http://${VPS_IP:-localhost}:9999/sms-email"}' --region "$REGION"
    echo "Secret creado: $SECRET_NAME"
fi
