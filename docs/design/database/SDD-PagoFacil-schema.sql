-- ============================================================
-- PagoFacil — Modelo de Datos (DDL)
-- Database-per-Service: cada bloque BC-XX corresponde a una
-- base de datos independiente provisionada por init-databases.sh
-- con la convención pagofacil_<servicio_slug>.
-- Los changelogs Liquibase se generan por bloque y se almacenan
-- en el repo pagofacil-migrations en Gitea del VPS.
-- Este archivo es el artefacto de diseño de referencia;
-- no existe un esquema global compartido en producción.
-- ============================================================


-- BC-01: identity-service → pagofacil_identity_service
-- -------------------------------------------------------

CREATE TABLE users (
    id              UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID            NOT NULL,
    email           VARCHAR(255)    NOT NULL,
    phone_number    VARCHAR(50),
    full_name       VARCHAR(255)    NOT NULL,
    date_of_birth   DATE,
    document_type   VARCHAR(50),
    document_id     VARCHAR(100),
    password_hash   VARCHAR(255)    NOT NULL,
    status          VARCHAR(50)     NOT NULL DEFAULT 'PENDING',
    -- PENDING | ACTIVE | SUSPENDED | BLOCKED
    failed_login_attempts   INT     NOT NULL DEFAULT 0,
    locked_until    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_users_email_tenant UNIQUE (email, tenant_id),
    CONSTRAINT ck_users_status CHECK (status IN ('PENDING','ACTIVE','SUSPENDED','BLOCKED'))
);

CREATE TABLE kyc_records (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users(id),
    status              VARCHAR(50) NOT NULL DEFAULT 'PENDING',
    -- PENDING | APPROVED | REJECTED | SUSPENDED
    provider_reference  VARCHAR(255),
    verification_result JSONB,
    verified_at         TIMESTAMPTZ,
    rejected_reason     TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_kyc_status CHECK (status IN ('PENDING','APPROVED','REJECTED','SUSPENDED'))
);

CREATE TABLE mfa_devices (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users(id),
    device_type         VARCHAR(50) NOT NULL,
    -- TOTP | SMS_OTP | EMAIL_OTP
    device_identifier   VARCHAR(255),
    secret_encrypted    VARCHAR(512),
    is_active           BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_mfa_device_type CHECK (device_type IN ('TOTP','SMS_OTP','EMAIL_OTP'))
);

CREATE TABLE sessions (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID        NOT NULL REFERENCES users(id),
    tenant_id           UUID        NOT NULL,
    refresh_token_hash  VARCHAR(255) NOT NULL,
    access_token_jti    VARCHAR(255),
    ip_address          INET,
    user_agent          TEXT,
    expires_at          TIMESTAMPTZ NOT NULL,
    revoked_at          TIMESTAMPTZ,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_sessions_refresh_token UNIQUE (refresh_token_hash)
);

CREATE TABLE outbox (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(255) NOT NULL,
    event_type      VARCHAR(255) NOT NULL,
    payload         JSONB        NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    status          VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    -- PENDING | PUBLISHED | FAILED
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMPTZ,
    CONSTRAINT ck_identity_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE TABLE processed_message (
    message_id      VARCHAR(255) PRIMARY KEY,
    consumer        VARCHAR(255) NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_tenant_id         ON users(tenant_id);
CREATE INDEX idx_users_email             ON users(email);
CREATE INDEX idx_kyc_records_user_id     ON kyc_records(user_id);
CREATE INDEX idx_mfa_devices_user_id     ON mfa_devices(user_id);
CREATE INDEX idx_sessions_user_id        ON sessions(user_id);
CREATE INDEX idx_sessions_expires_at     ON sessions(expires_at);
CREATE INDEX idx_identity_outbox_status  ON outbox(status, created_at);


-- BC-02: wallet-service → pagofacil_wallet_service
-- --------------------------------------------------

CREATE TABLE wallets (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID            NOT NULL,
    tenant_id           UUID            NOT NULL,
    available_balance   NUMERIC(20,4)   NOT NULL DEFAULT 0,
    reserved_balance    NUMERIC(20,4)   NOT NULL DEFAULT 0,
    currency            VARCHAR(10)     NOT NULL DEFAULT 'USD',
    status              VARCHAR(50)     NOT NULL DEFAULT 'ACTIVE',
    -- ACTIVE | SUSPENDED | CLOSED
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_wallets_user_tenant UNIQUE (user_id, tenant_id),
    CONSTRAINT ck_wallets_status CHECK (status IN ('ACTIVE','SUSPENDED','CLOSED')),
    CONSTRAINT ck_wallets_balance_non_negative CHECK (available_balance >= 0),
    CONSTRAINT ck_wallets_reserved_non_negative CHECK (reserved_balance >= 0)
);

CREATE TABLE wallet_transactions (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id           UUID            NOT NULL REFERENCES wallets(id),
    tenant_id           UUID            NOT NULL,
    transaction_type    VARCHAR(50)     NOT NULL,
    -- DEPOSIT | TRANSFER_DEBIT | TRANSFER_CREDIT | WITHDRAWAL | REVERSAL
    amount              NUMERIC(20,4)   NOT NULL,
    currency            VARCHAR(10)     NOT NULL,
    status              VARCHAR(50)     NOT NULL DEFAULT 'PENDING',
    -- PENDING | CONFIRMED | REVERSED | FAILED
    idempotency_key     VARCHAR(255)    NOT NULL,
    correlation_id      UUID            NOT NULL,
    reference_tx_id     UUID,
    created_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_wallet_tx_idempotency UNIQUE (idempotency_key),
    CONSTRAINT ck_wallet_tx_type CHECK (transaction_type IN ('DEPOSIT','TRANSFER_DEBIT','TRANSFER_CREDIT','WITHDRAWAL','REVERSAL')),
    CONSTRAINT ck_wallet_tx_status CHECK (status IN ('PENDING','CONFIRMED','REVERSED','FAILED'))
);

CREATE TABLE transaction_limits (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id       UUID        NOT NULL REFERENCES wallets(id),
    tenant_id       UUID        NOT NULL,
    limit_type      VARCHAR(50) NOT NULL,
    -- DEPOSIT | TRANSFER | WITHDRAWAL
    period          VARCHAR(20) NOT NULL,
    -- DAILY | WEEKLY | MONTHLY
    max_amount      NUMERIC(20,4) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_tx_limits_wallet_type_period UNIQUE (wallet_id, limit_type, period)
);

CREATE TABLE linked_bank_accounts (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    wallet_id       UUID        NOT NULL REFERENCES wallets(id),
    tenant_id       UUID        NOT NULL,
    bank_code       VARCHAR(50) NOT NULL,
    bank_name       VARCHAR(255) NOT NULL,
    account_number  VARCHAR(255) NOT NULL,
    account_type    VARCHAR(50),
    holder_name     VARCHAR(255) NOT NULL,
    status          VARCHAR(50) NOT NULL DEFAULT 'PENDING_VERIFICATION',
    -- PENDING_VERIFICATION | VERIFIED | REJECTED
    verified_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_linked_bank_status CHECK (status IN ('PENDING_VERIFICATION','VERIFIED','REJECTED'))
);

CREATE TABLE outbox (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(255) NOT NULL,
    event_type      VARCHAR(255) NOT NULL,
    payload         JSONB        NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    status          VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMPTZ,
    CONSTRAINT ck_wallet_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE TABLE processed_message (
    message_id      VARCHAR(255) PRIMARY KEY,
    consumer        VARCHAR(255) NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_wallets_user_id             ON wallets(user_id);
CREATE INDEX idx_wallets_tenant_id           ON wallets(tenant_id);
CREATE INDEX idx_wallet_tx_wallet_id         ON wallet_transactions(wallet_id);
CREATE INDEX idx_wallet_tx_correlation_id    ON wallet_transactions(correlation_id);
CREATE INDEX idx_wallet_tx_created_at        ON wallet_transactions(created_at DESC);
CREATE INDEX idx_tx_limits_wallet_id         ON transaction_limits(wallet_id);
CREATE INDEX idx_linked_bank_wallet_id       ON linked_bank_accounts(wallet_id);
CREATE INDEX idx_wallet_outbox_status        ON outbox(status, created_at);


-- BC-03: fraud-compliance-service → pagofacil_fraud_compliance_service
-- ---------------------------------------------------------------------

CREATE TABLE fraud_rules (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    rule_code       VARCHAR(100) NOT NULL,
    description     TEXT,
    rule_type       VARCHAR(50) NOT NULL,
    -- VELOCITY | AMOUNT_THRESHOLD | GEOLOCATION | BEHAVIORAL
    parameters      JSONB       NOT NULL,
    risk_level      VARCHAR(20) NOT NULL,
    -- LOW | MEDIUM | HIGH | CRITICAL
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_fraud_rules_code_tenant UNIQUE (rule_code, tenant_id)
);

CREATE TABLE risk_evaluations (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    user_id         UUID        NOT NULL,
    transaction_id  UUID,
    correlation_id  UUID        NOT NULL,
    evaluation_type VARCHAR(50) NOT NULL,
    -- AML | FRAUD
    result          VARCHAR(20) NOT NULL,
    -- APPROVED | BLOCKED | ESCALATED
    risk_level      VARCHAR(20) NOT NULL,
    triggered_rules JSONB,
    evaluated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE compliance_alerts (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    alert_type      VARCHAR(20) NOT NULL,
    -- AML | FRAUD
    user_id         UUID        NOT NULL,
    transaction_id  UUID,
    correlation_id  UUID        NOT NULL,
    risk_level      VARCHAR(20) NOT NULL,
    -- LOW | MEDIUM | HIGH | CRITICAL
    status          VARCHAR(20) NOT NULL DEFAULT 'OPEN',
    -- OPEN | UNDER_REVIEW | APPROVED | REJECTED | ESCALATED
    triggered_rule  VARCHAR(100),
    resolution_actor VARCHAR(255),
    resolution_reason TEXT,
    resolved_at     TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_alert_type CHECK (alert_type IN ('AML','FRAUD')),
    CONSTRAINT ck_alert_risk_level CHECK (risk_level IN ('LOW','MEDIUM','HIGH','CRITICAL')),
    CONSTRAINT ck_alert_status CHECK (status IN ('OPEN','UNDER_REVIEW','APPROVED','REJECTED','ESCALATED'))
);

CREATE TABLE outbox (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(255) NOT NULL,
    event_type      VARCHAR(255) NOT NULL,
    payload         JSONB        NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    status          VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMPTZ,
    CONSTRAINT ck_fraud_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE TABLE processed_message (
    message_id      VARCHAR(255) PRIMARY KEY,
    consumer        VARCHAR(255) NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_compliance_alerts_tenant_id    ON compliance_alerts(tenant_id);
CREATE INDEX idx_compliance_alerts_user_id      ON compliance_alerts(user_id);
CREATE INDEX idx_compliance_alerts_status       ON compliance_alerts(status);
CREATE INDEX idx_compliance_alerts_correlation  ON compliance_alerts(correlation_id);
CREATE INDEX idx_risk_eval_correlation_id       ON risk_evaluations(correlation_id);
CREATE INDEX idx_fraud_outbox_status            ON outbox(status, created_at);


-- BC-04: notification-service → pagofacil_notification_service
-- -------------------------------------------------------------

CREATE TABLE notification_templates (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    template_code   VARCHAR(100) NOT NULL,
    channel         VARCHAR(20) NOT NULL,
    -- EMAIL | SMS | PUSH
    subject         VARCHAR(255),
    body_template   TEXT        NOT NULL,
    is_active       BOOLEAN     NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_notification_template UNIQUE (template_code, channel, tenant_id)
);

CREATE TABLE notification_preferences (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL,
    tenant_id       UUID        NOT NULL,
    event_type      VARCHAR(100) NOT NULL,
    preferred_channel VARCHAR(20) NOT NULL DEFAULT 'EMAIL',
    is_enabled      BOOLEAN     NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_notification_pref UNIQUE (user_id, event_type)
);

CREATE TABLE notifications (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID        NOT NULL,
    tenant_id       UUID        NOT NULL,
    channel         VARCHAR(20) NOT NULL,
    template_code   VARCHAR(100),
    destination     VARCHAR(255) NOT NULL,
    subject         VARCHAR(255),
    body            TEXT,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    -- PENDING | SENT | FAILED
    correlation_id  UUID,
    provider_message_id VARCHAR(255),
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_notification_status CHECK (status IN ('PENDING','SENT','FAILED'))
);

CREATE TABLE processed_message (
    message_id      VARCHAR(255) PRIMARY KEY,
    consumer        VARCHAR(255) NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id          ON notifications(user_id);
CREATE INDEX idx_notifications_correlation_id   ON notifications(correlation_id);
CREATE INDEX idx_notifications_status           ON notifications(status);


-- BC-05: integration-service → pagofacil_integration_service
-- Saga coordinator tables + outbox + reconciliation
-- -----------------------------------------------------------

CREATE TABLE saga_instance (
    saga_id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID        NOT NULL,
    saga_type       VARCHAR(50) NOT NULL,
    -- DEPOSIT | TRANSFER | WITHDRAWAL
    state           VARCHAR(50) NOT NULL DEFAULT 'INITIATED',
    -- INITIATED | IN_PROGRESS | COMPLETED | COMPENSATING | FAILED
    current_step    VARCHAR(100),
    payload         JSONB,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_saga_type CHECK (saga_type IN ('DEPOSIT','TRANSFER','WITHDRAWAL')),
    CONSTRAINT ck_saga_state CHECK (state IN ('INITIATED','IN_PROGRESS','COMPLETED','COMPENSATING','FAILED'))
);

CREATE TABLE saga_step_log (
    id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id                 UUID        NOT NULL REFERENCES saga_instance(saga_id),
    step_name               VARCHAR(100) NOT NULL,
    status                  VARCHAR(50) NOT NULL,
    -- PENDING | COMPLETED | COMPENSATED | FAILED
    compensation_payload    JSONB,
    executed_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT ck_saga_step_status CHECK (status IN ('PENDING','COMPLETED','COMPENSATED','FAILED'))
);

CREATE TABLE external_integration_events (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    saga_id             UUID        REFERENCES saga_instance(saga_id),
    tenant_id           UUID        NOT NULL,
    source_system       VARCHAR(100) NOT NULL,
    event_type          VARCHAR(100) NOT NULL,
    payload             JSONB       NOT NULL,
    idempotency_key     VARCHAR(255) NOT NULL,
    processed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_ext_event_idempotency UNIQUE (idempotency_key, source_system)
);

CREATE TABLE reconciliation_records (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    external_reference  VARCHAR(255) NOT NULL,
    internal_tx_id      UUID,
    source_system       VARCHAR(100) NOT NULL,
    reconciliation_date DATE        NOT NULL,
    status              VARCHAR(50) NOT NULL,
    -- MATCHED | UNMATCHED | PENDING
    details             JSONB,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE outbox (
    id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    aggregate_type  VARCHAR(100) NOT NULL,
    aggregate_id    VARCHAR(255) NOT NULL,
    event_type      VARCHAR(255) NOT NULL,
    payload         JSONB        NOT NULL,
    topic           VARCHAR(255) NOT NULL,
    status          VARCHAR(50)  NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    published_at    TIMESTAMPTZ,
    CONSTRAINT ck_integration_outbox_status CHECK (status IN ('PENDING','PUBLISHED','FAILED'))
);

CREATE TABLE processed_message (
    message_id      VARCHAR(255) PRIMARY KEY,
    consumer        VARCHAR(255) NOT NULL,
    processed_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_saga_instance_state      ON saga_instance(state);
CREATE INDEX idx_saga_instance_tenant     ON saga_instance(tenant_id);
CREATE INDEX idx_saga_step_log_saga_id    ON saga_step_log(saga_id);
CREATE INDEX idx_integration_outbox_status ON outbox(status, created_at);
CREATE INDEX idx_reconciliation_date      ON reconciliation_records(reconciliation_date);


-- BC-07: projection-service → pagofacil_readmodel
-- Read model CQRS. Tablas desnormalizadas optimizadas para
-- extracción ETL (MS1 Spark). Solo el projection-service escribe
-- aquí. MS1 tiene credenciales de solo lectura.
-- ---------------------------------------------------------------

CREATE TABLE report_transactions (
    id                  UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID            NOT NULL,
    transaction_id      UUID            NOT NULL,
    transaction_type    VARCHAR(50)     NOT NULL,
    status              VARCHAR(50)     NOT NULL,
    amount              NUMERIC(20,4)   NOT NULL,
    currency            VARCHAR(10)     NOT NULL,
    user_id             UUID            NOT NULL,
    user_email          VARCHAR(255),
    user_full_name      VARCHAR(255),
    wallet_id           UUID,
    correlation_id      UUID,
    created_at          TIMESTAMPTZ     NOT NULL,
    confirmed_at        TIMESTAMPTZ,
    CONSTRAINT uq_rm_transaction_id UNIQUE (transaction_id)
);

CREATE TABLE report_compliance_alerts (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    alert_id            UUID        NOT NULL,
    alert_type          VARCHAR(20) NOT NULL,
    risk_level          VARCHAR(20) NOT NULL,
    status              VARCHAR(20) NOT NULL,
    user_id             UUID        NOT NULL,
    user_email          VARCHAR(255),
    user_full_name      VARCHAR(255),
    transaction_id      UUID,
    triggered_rule      VARCHAR(100),
    resolution_actor    VARCHAR(255),
    created_at          TIMESTAMPTZ NOT NULL,
    resolved_at         TIMESTAMPTZ,
    CONSTRAINT uq_rm_alert_id UNIQUE (alert_id)
);

CREATE TABLE report_users (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    user_id             UUID        NOT NULL,
    email               VARCHAR(255),
    full_name           VARCHAR(255),
    user_status         VARCHAR(50),
    kyc_status          VARCHAR(50),
    kyc_approved_at     TIMESTAMPTZ,
    registered_at       TIMESTAMPTZ NOT NULL,
    CONSTRAINT uq_rm_user_id UNIQUE (user_id)
);

CREATE INDEX idx_rm_transactions_tenant_id      ON report_transactions(tenant_id);
CREATE INDEX idx_rm_transactions_user_id        ON report_transactions(user_id);
CREATE INDEX idx_rm_transactions_created_at     ON report_transactions(created_at DESC);
CREATE INDEX idx_rm_transactions_type_status    ON report_transactions(transaction_type, status);
CREATE INDEX idx_rm_alerts_tenant_id            ON report_compliance_alerts(tenant_id);
CREATE INDEX idx_rm_alerts_created_at           ON report_compliance_alerts(created_at DESC);
CREATE INDEX idx_rm_users_tenant_id             ON report_users(tenant_id);


-- BC-07: report-extraction-service (MS1) → pagofacil_reporting
-- Catálogo de esquemas y metadatos de ejecuciones.
-- MS1 lee report_schema_catalog para validar el esquema extraído.
-- ---------------------------------------------------------------

CREATE TABLE report_schema_catalog (
    report_type         VARCHAR(100)    PRIMARY KEY,
    schema_version      VARCHAR(20)     NOT NULL,
    description         TEXT,
    columns             JSONB           NOT NULL,
    integrity_rules     JSONB,
    source_table        VARCHAR(255)    NOT NULL,
    updated_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

CREATE TABLE report_executions (
    id                  UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id           UUID        NOT NULL,
    report_type         VARCHAR(100) NOT NULL REFERENCES report_schema_catalog(report_type),
    output_format       VARCHAR(10) NOT NULL,
    -- PDF | XLS | CSV
    status              VARCHAR(50) NOT NULL DEFAULT 'QUEUED',
    -- QUEUED | EXTRACTING | PROCESSING | GENERATING_FORMAT | COMPLETED | FAILED
    requested_by        VARCHAR(255),
    period_from         DATE,
    period_to           DATE,
    parquet_raw_path    VARCHAR(512),
    parquet_proc_path   VARCHAR(512),
    output_path         VARCHAR(512),
    error_message       TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at        TIMESTAMPTZ,
    CONSTRAINT ck_report_execution_status CHECK (status IN ('QUEUED','EXTRACTING','PROCESSING','GENERATING_FORMAT','COMPLETED','FAILED')),
    CONSTRAINT ck_report_output_format CHECK (output_format IN ('PDF','XLS','CSV'))
);

CREATE INDEX idx_report_executions_tenant_id    ON report_executions(tenant_id);
CREATE INDEX idx_report_executions_status       ON report_executions(status);
CREATE INDEX idx_report_executions_created_at   ON report_executions(created_at DESC);
