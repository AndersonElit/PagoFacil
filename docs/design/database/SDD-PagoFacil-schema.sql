-- ============================================================
-- PagoFacil — Schema DDL de Diseño (artefacto de referencia)
-- Persistencia poliglota: todos los bounded contexts usan
-- PostgreSQL 16.3. El read model (pagofacil_readmodel) es
-- propiedad exclusiva del projection-service.
--
-- IMPORTANTE: Este archivo es el artefacto de diseño unificado.
-- En producción cada bloque BC-XX es propiedad de su servicio:
--   scaffold-all-services.sh lo extrae a db/<servicio>/changelog/00001_initial_schema.yaml
--   de cada servicio, aplicado por Liquibase standalone (run-liquibase-migrations.sh)
--   sobre su BD propia (<prefijo>_<svc_slug>).
-- No existe un schema global compartido en producción.
-- ============================================================


-- ============================================================
-- BC-01: identity-service → pagofacil_identity_service
-- ============================================================

CREATE TABLE users (
    user_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    email           VARCHAR(320) NOT NULL,
    full_name       VARCHAR(255) NOT NULL,
    document_type   VARCHAR(20)  NOT NULL,
    document_number VARCHAR(50)  NOT NULL,
    account_status  VARCHAR(30)  NOT NULL DEFAULT 'PENDIENTE_KYC',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT uq_users_email            UNIQUE (email),
    CONSTRAINT uq_users_document         UNIQUE (document_type, document_number),
    CONSTRAINT chk_users_status          CHECK (account_status IN ('PENDIENTE_KYC','ACTIVA','SUSPENDIDA','BLOQUEADA'))
);

CREATE INDEX idx_users_tenant        ON users (tenant_id);
CREATE INDEX idx_users_account_status ON users (account_status);

CREATE TABLE kyc_registrations (
    kyc_id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users(user_id),
    provider_reference  VARCHAR(255),
    result              VARCHAR(20)  NOT NULL DEFAULT 'PENDIENTE',
    document_data       JSONB,
    submitted_at        TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at         TIMESTAMPTZ,
    CONSTRAINT chk_kyc_result CHECK (result IN ('PENDIENTE','APROBADO','RECHAZADO','EN_REVISION'))
);

CREATE INDEX idx_kyc_user_id ON kyc_registrations (user_id);

CREATE TABLE authentication_credentials (
    credential_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL UNIQUE REFERENCES users(user_id),
    password_hash   VARCHAR(255) NOT NULL,
    failed_attempts INT          NOT NULL DEFAULT 0,
    last_failed_at  TIMESTAMPTZ,
    locked_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE TABLE mfa_configs (
    mfa_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        UUID        NOT NULL REFERENCES users(user_id),
    mfa_type       VARCHAR(20)  NOT NULL,
    is_active      BOOLEAN      NOT NULL DEFAULT false,
    secret_enc     TEXT,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_mfa_type CHECK (mfa_type IN ('TOTP','SMS','EMAIL'))
);

CREATE INDEX idx_mfa_user_id ON mfa_configs (user_id);

CREATE TABLE active_sessions (
    session_id      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL REFERENCES users(user_id),
    cognito_sub     VARCHAR(255) NOT NULL,
    ip_address      INET,
    user_agent      TEXT,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ  NOT NULL,
    invalidated_at  TIMESTAMPTZ
);

CREATE INDEX idx_sessions_user_id    ON active_sessions (user_id);
CREATE INDEX idx_sessions_expires_at ON active_sessions (expires_at);


-- ============================================================
-- BC-02: wallet-service → pagofacil_wallet_service
-- ============================================================

CREATE TABLE wallets (
    wallet_id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id            UUID         NOT NULL,
    tenant_id          UUID         NOT NULL,
    available_balance  NUMERIC(18,2) NOT NULL DEFAULT 0,
    pending_balance    NUMERIC(18,2) NOT NULL DEFAULT 0,
    currency           VARCHAR(3)    NOT NULL DEFAULT 'USD',
    created_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at         TIMESTAMPTZ   NOT NULL DEFAULT now(),
    CONSTRAINT uq_wallets_user_tenant     UNIQUE (user_id, tenant_id),
    CONSTRAINT chk_wallets_available_gte0 CHECK (available_balance >= 0),
    CONSTRAINT chk_wallets_pending_gte0   CHECK (pending_balance >= 0)
);

CREATE INDEX idx_wallets_tenant ON wallets (tenant_id);

CREATE TABLE transaction_limits (
    limit_id            UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID         NOT NULL,
    max_per_operation   NUMERIC(18,2) NOT NULL,
    max_daily           NUMERIC(18,2) NOT NULL,
    max_monthly         NUMERIC(18,2) NOT NULL,
    max_ops_per_period  INT           NOT NULL,
    period_days         INT           NOT NULL DEFAULT 1,
    created_at          TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX idx_limits_tenant ON transaction_limits (tenant_id);

CREATE TABLE transactions (
    transaction_id         UUID         PRIMARY KEY,
    correlation_id         UUID         NOT NULL,
    idempotency_key        VARCHAR(255)  NOT NULL,
    wallet_id              UUID         NOT NULL REFERENCES wallets(wallet_id),
    tenant_id              UUID         NOT NULL,
    operation_type         VARCHAR(20)   NOT NULL,
    amount                 NUMERIC(18,2) NOT NULL,
    currency               VARCHAR(3)    NOT NULL DEFAULT 'USD',
    status                 VARCHAR(20)   NOT NULL DEFAULT 'PENDIENTE',
    counterpart_wallet_id  UUID,
    external_reference     VARCHAR(255),
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    resolved_at            TIMESTAMPTZ,
    CONSTRAINT uq_transactions_idempotency UNIQUE (idempotency_key, tenant_id),
    CONSTRAINT chk_tx_type   CHECK (operation_type IN ('DEPOSITO','RETIRO','TRANSFERENCIA')),
    CONSTRAINT chk_tx_status CHECK (status IN ('PENDIENTE','EN_PROCESO','CONFIRMADA','FALLIDA','RETENIDA')),
    CONSTRAINT chk_tx_amount CHECK (amount > 0)
);

CREATE INDEX idx_tx_wallet_id   ON transactions (wallet_id);
CREATE INDEX idx_tx_tenant_id   ON transactions (tenant_id);
CREATE INDEX idx_tx_status      ON transactions (status);
CREATE INDEX idx_tx_created_at  ON transactions (created_at);

CREATE TABLE fund_sources (
    source_id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL,
    tenant_id           UUID        NOT NULL,
    bank_name           VARCHAR(255) NOT NULL,
    account_number_enc  TEXT         NOT NULL,
    account_type        VARCHAR(20)  NOT NULL,
    is_active           BOOLEAN      NOT NULL DEFAULT true,
    created_at          TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_fund_sources_user ON fund_sources (user_id, tenant_id);

-- Transactional Outbox — wallet-service
CREATE TABLE outbox (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(255) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    CONSTRAINT chk_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_outbox_status_created ON outbox (status, created_at);

-- Idempotencia de consumers Kafka — wallet-service
CREATE TABLE processed_message (
    message_id   VARCHAR(255) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- ============================================================
-- BC-03: fraud-service → pagofacil_fraud_service
-- ============================================================

CREATE TABLE fraud_rules (
    rule_id     UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id   UUID        NOT NULL,
    name        VARCHAR(255) NOT NULL,
    rule_type   VARCHAR(30)  NOT NULL,
    threshold   NUMERIC(18,2),
    action      VARCHAR(20)  NOT NULL,
    config      JSONB,
    is_active   BOOLEAN      NOT NULL DEFAULT true,
    created_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_rule_type   CHECK (rule_type IN ('MONTO','FRECUENCIA','PATRON','DESTINATARIO')),
    CONSTRAINT chk_rule_action CHECK (action IN ('BLOQUEAR','RETENER'))
);

CREATE INDEX idx_fraud_rules_tenant ON fraud_rules (tenant_id, is_active);

CREATE TABLE aml_verifications (
    verification_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id    UUID        NOT NULL,
    user_id           UUID        NOT NULL,
    counterpart_id    UUID,
    lists_checked     TEXT[]      NOT NULL DEFAULT '{}',
    result            VARCHAR(20)  NOT NULL,
    match_details     JSONB,
    verified_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_aml_result CHECK (result IN ('NO_MATCH','MATCH','INCIERTO'))
);

CREATE INDEX idx_aml_transaction ON aml_verifications (transaction_id);

CREATE TABLE fraud_alerts (
    alert_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id  UUID        NOT NULL,
    user_id         UUID        NOT NULL,
    tenant_id       UUID        NOT NULL,
    severity        VARCHAR(10)  NOT NULL,
    status          VARCHAR(20)  NOT NULL DEFAULT 'PENDIENTE',
    alert_type      VARCHAR(10)  NOT NULL DEFAULT 'FRAUDE',
    rule_triggered  VARCHAR(255),
    evaluation_data JSONB,
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at     TIMESTAMPTZ,
    auditor_id      UUID,
    auditor_decision VARCHAR(20),
    justification   TEXT,
    CONSTRAINT chk_alert_severity CHECK (severity IN ('BAJA','MEDIA','ALTA','CRITICA')),
    CONSTRAINT chk_alert_status   CHECK (status IN ('PENDIENTE','APROBADA','RECHAZADA')),
    CONSTRAINT chk_alert_type     CHECK (alert_type IN ('FRAUDE','AML'))
);

CREATE INDEX idx_alerts_tenant_status ON fraud_alerts (tenant_id, status);
CREATE INDEX idx_alerts_transaction   ON fraud_alerts (transaction_id);

-- Transactional Outbox — fraud-service
CREATE TABLE outbox (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(255) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    CONSTRAINT chk_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_outbox_status_created ON outbox (status, created_at);

-- Idempotencia de consumers Kafka — fraud-service
CREATE TABLE processed_message (
    message_id   VARCHAR(255) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- ============================================================
-- BC-04: notification-service → pagofacil_notification_service
-- ============================================================

CREATE TABLE notification_templates (
    template_id   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    event_type    VARCHAR(100) NOT NULL UNIQUE,
    channel       VARCHAR(20)  NOT NULL,
    subject       VARCHAR(255),
    body_template TEXT         NOT NULL,
    is_active     BOOLEAN      NOT NULL DEFAULT true,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_channel CHECK (channel IN ('EMAIL','SMS','PUSH'))
);

CREATE TABLE notifications (
    notification_id  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id          UUID        NOT NULL,
    tenant_id        UUID        NOT NULL,
    event_type       VARCHAR(100) NOT NULL,
    channel          VARCHAR(20)  NOT NULL,
    recipient        VARCHAR(320) NOT NULL,
    status           VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    correlation_id   UUID,
    sent_at          TIMESTAMPTZ,
    failed_at        TIMESTAMPTZ,
    failure_reason   TEXT,
    created_at       TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_notif_status  CHECK (status IN ('PENDING','SENT','FAILED')),
    CONSTRAINT chk_notif_channel CHECK (channel IN ('EMAIL','SMS','PUSH'))
);

CREATE INDEX idx_notif_user_id   ON notifications (user_id);
CREATE INDEX idx_notif_status    ON notifications (status, created_at);

-- Idempotencia de consumers Kafka — notification-service
CREATE TABLE processed_message (
    message_id   VARCHAR(255) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- ============================================================
-- BC-06: integration-service → pagofacil_integration_service
-- Incluye tablas de Saga LRA y Outbox (orquestador)
-- ============================================================

CREATE TABLE saga_instance (
    saga_id       UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_type     VARCHAR(30)  NOT NULL,
    state         VARCHAR(20)  NOT NULL DEFAULT 'INICIADA',
    current_step  VARCHAR(100),
    payload       JSONB        NOT NULL,
    correlation_id UUID        NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_saga_type  CHECK (saga_type IN ('DEPOSITO','RETIRO','TRANSFERENCIA','CONCILIACION')),
    CONSTRAINT chk_saga_state CHECK (state IN ('INICIADA','EN_PROGRESO','COMPLETADA','COMPENSANDO','COMPENSADA','FALLIDA'))
);

CREATE INDEX idx_saga_state         ON saga_instance (state);
CREATE INDEX idx_saga_correlation   ON saga_instance (correlation_id);

CREATE TABLE saga_step_log (
    id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id              UUID        NOT NULL REFERENCES saga_instance(saga_id),
    step_name            VARCHAR(100) NOT NULL,
    status               VARCHAR(20)  NOT NULL,
    compensation_payload JSONB,
    executed_at          TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT chk_step_status CHECK (status IN ('COMPLETADO','COMPENSADO','FALLIDO'))
);

CREATE INDEX idx_step_log_saga_id ON saga_step_log (saga_id);

CREATE TABLE external_requests (
    request_id        UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id           UUID        REFERENCES saga_instance(saga_id),
    system_name       VARCHAR(100) NOT NULL,
    operation         VARCHAR(100) NOT NULL,
    request_payload   JSONB        NOT NULL,
    response_payload  JSONB,
    status            VARCHAR(20)  NOT NULL DEFAULT 'SENT',
    correlation_id    UUID         NOT NULL,
    sent_at           TIMESTAMPTZ  NOT NULL DEFAULT now(),
    resolved_at       TIMESTAMPTZ,
    CONSTRAINT chk_ext_req_status CHECK (status IN ('SENT','CONFIRMED','REJECTED','TIMEOUT'))
);

CREATE INDEX idx_ext_req_saga       ON external_requests (saga_id);
CREATE INDEX idx_ext_req_correlation ON external_requests (correlation_id);

-- Transactional Outbox — integration-service
CREATE TABLE outbox (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type VARCHAR(100) NOT NULL,
    aggregate_id   UUID         NOT NULL,
    event_type     VARCHAR(100) NOT NULL,
    payload        JSONB        NOT NULL,
    topic          VARCHAR(255) NOT NULL,
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now(),
    published_at   TIMESTAMPTZ,
    status         VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    CONSTRAINT chk_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE INDEX idx_outbox_status_created ON outbox (status, created_at);

-- Idempotencia de consumers Kafka — integration-service
CREATE TABLE processed_message (
    message_id   VARCHAR(255) PRIMARY KEY,
    consumer     VARCHAR(100) NOT NULL,
    processed_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);


-- ============================================================
-- BC-07 (Reporting): reporting-context → pagofacil_reporting
-- ============================================================

CREATE TABLE report_schema_catalog (
    report_type      VARCHAR(100) PRIMARY KEY,
    schema_version   INT          NOT NULL DEFAULT 1,
    columns          JSONB        NOT NULL,
    integrity_rules  JSONB,
    source_tables    TEXT[]       NOT NULL DEFAULT '{}',
    formats          TEXT[]       NOT NULL DEFAULT '{PDF,CSV}',
    updated_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- Registro de jobs de extracción/procesamiento
CREATE TABLE report_jobs (
    report_id    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    report_type  VARCHAR(100) NOT NULL REFERENCES report_schema_catalog(report_type),
    period_from  DATE         NOT NULL,
    period_to    DATE         NOT NULL,
    formats      TEXT[]       NOT NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'ENCOLADO',
    requested_by UUID         NOT NULL,
    requested_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    completed_at TIMESTAMPTZ,
    s3_key_raw   TEXT,
    s3_key_proc  TEXT,
    error_detail TEXT,
    CONSTRAINT chk_report_status CHECK (status IN ('ENCOLADO','EXTRAYENDO','PROCESANDO','COMPLETADO','FALLIDO'))
);

CREATE INDEX idx_report_jobs_status ON report_jobs (status, requested_at);


-- ============================================================
-- CQRS Read Model: projection-service → pagofacil_readmodel
-- Es el único escritor. audit-service y MS1 solo leen.
-- ============================================================

CREATE TABLE report_transactions (
    transaction_id       UUID         PRIMARY KEY,
    correlation_id       UUID         NOT NULL,
    user_id              UUID         NOT NULL,
    tenant_id            UUID         NOT NULL,
    wallet_id            UUID         NOT NULL,
    operation_type       VARCHAR(20)  NOT NULL,
    amount               NUMERIC(18,2) NOT NULL,
    currency             VARCHAR(3)   NOT NULL,
    status               VARCHAR(20)  NOT NULL,
    counterpart_user_id  UUID,
    external_reference   VARCHAR(255),
    created_at           TIMESTAMPTZ  NOT NULL,
    resolved_at          TIMESTAMPTZ,
    projected_at         TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_rtx_user_id    ON report_transactions (user_id);
CREATE INDEX idx_rtx_tenant_id  ON report_transactions (tenant_id);
CREATE INDEX idx_rtx_status     ON report_transactions (status);
CREATE INDEX idx_rtx_created_at ON report_transactions (created_at);

CREATE TABLE report_alerts (
    alert_id          UUID        PRIMARY KEY,
    transaction_id    UUID        NOT NULL,
    user_id           UUID        NOT NULL,
    tenant_id         UUID        NOT NULL,
    severity          VARCHAR(10)  NOT NULL,
    status            VARCHAR(20)  NOT NULL,
    alert_type        VARCHAR(10)  NOT NULL,
    rule_triggered    VARCHAR(255),
    created_at        TIMESTAMPTZ  NOT NULL,
    resolved_at       TIMESTAMPTZ,
    auditor_decision  VARCHAR(20),
    projected_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_ralerts_tenant_status ON report_alerts (tenant_id, status);
CREATE INDEX idx_ralerts_transaction   ON report_alerts (transaction_id);

CREATE TABLE report_wallets (
    wallet_id          UUID         PRIMARY KEY,
    user_id            UUID         NOT NULL,
    tenant_id          UUID         NOT NULL,
    available_balance  NUMERIC(18,2) NOT NULL,
    pending_balance    NUMERIC(18,2) NOT NULL,
    currency           VARCHAR(3)   NOT NULL,
    last_updated       TIMESTAMPTZ  NOT NULL,
    projected_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_rwallets_tenant ON report_wallets (tenant_id);
CREATE INDEX idx_rwallets_user   ON report_wallets (user_id);

CREATE TABLE report_reconciliations (
    reconciliation_id  UUID         PRIMARY KEY,
    correlation_id     UUID         NOT NULL,
    transaction_id     UUID,
    tenant_id          UUID         NOT NULL,
    discrepancy_type   VARCHAR(50),
    internal_amount    NUMERIC(18,2),
    external_amount    NUMERIC(18,2),
    status             VARCHAR(20)  NOT NULL,
    detected_at        TIMESTAMPTZ  NOT NULL,
    projected_at       TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX idx_recon_tenant ON report_reconciliations (tenant_id);
CREATE INDEX idx_recon_status ON report_reconciliations (status, detected_at);
