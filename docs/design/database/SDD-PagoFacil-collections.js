// ============================================================
// PagoFacil — Modelo de Datos MongoDB (Colecciones)
// BC-06: audit-service → pagofacil_audit_service
// Motor: MongoDB 7 (append-only)
// Modo de escritura: insert-only; ningún documento puede ser
// actualizado ni eliminado desde ninguna interfaz del sistema.
// ============================================================


// BC-06: audit-service → pagofacil_audit_service
// -------------------------------------------------------

db.createCollection("audit_traces", {
    validator: {
        $jsonSchema: {
            bsonType: "object",
            title: "AuditTrace",
            description: "Traza inmutable de un evento de negocio. Append-only.",
            required: [
                "eventType",
                "actor",
                "action",
                "tenantId",
                "correlationId",
                "ipAddress",
                "timestamp"
            ],
            properties: {
                _id: {
                    bsonType: "objectId"
                },
                traceId: {
                    bsonType: "string",
                    description: "UUID v4 único de la traza. Generado por el audit-service al momento de inserción."
                },
                eventType: {
                    bsonType: "string",
                    description: "Tipo de evento de negocio. Ej: USER_REGISTERED, KYC_APPROVED, DEPOSIT_COMPLETED, ALERT_RESOLVED.",
                    minLength: 1
                },
                actor: {
                    bsonType: "string",
                    description: "Identificador del actor que realizó la acción: userId, serviceId o SYSTEM."
                },
                actorRole: {
                    bsonType: "string",
                    description: "Rol del actor al momento del evento: USER, ADMIN, FRAUD_ANALYST, COMPLIANCE_OFFICER, SYSTEM.",
                    enum: ["USER", "ADMIN", "FRAUD_ANALYST", "COMPLIANCE_OFFICER", "SYSTEM", "EXTERNAL_SYSTEM"]
                },
                action: {
                    bsonType: "string",
                    description: "Descripción de la acción ejecutada. Ej: CREATED, APPROVED, REJECTED, SUSPENDED, TRANSFERRED."
                },
                tenantId: {
                    bsonType: "string",
                    description: "Identificador del tenant (UUID v4 como string)."
                },
                userId: {
                    bsonType: ["string", "null"],
                    description: "Identificador del usuario afectado por el evento. Nulo para eventos de sistema."
                },
                resourceType: {
                    bsonType: "string",
                    description: "Tipo de recurso afectado. Ej: USER, WALLET, TRANSACTION, COMPLIANCE_ALERT."
                },
                resourceId: {
                    bsonType: ["string", "null"],
                    description: "Identificador del recurso afectado (UUID como string)."
                },
                correlationId: {
                    bsonType: "string",
                    description: "UUID de correlación que agrupa todos los eventos de la misma operación o saga."
                },
                sagaId: {
                    bsonType: ["string", "null"],
                    description: "UUID de la saga a la que pertenece el evento. Nulo para operaciones no-saga."
                },
                ipAddress: {
                    bsonType: "string",
                    description: "IP de origen de la solicitud. IPv4 o IPv6."
                },
                userAgent: {
                    bsonType: ["string", "null"],
                    description: "User-Agent del cliente que originó la solicitud."
                },
                timestamp: {
                    bsonType: "date",
                    description: "Fecha y hora UTC del evento. Inmutable desde la inserción."
                },
                metadata: {
                    bsonType: ["object", "null"],
                    description: "Metadatos adicionales del evento. No deben incluir PII en texto plano.",
                    additionalProperties: true
                },
                sourceService: {
                    bsonType: "string",
                    description: "Microservicio que publicó el evento. Ej: identity-service, wallet-service."
                }
            },
            additionalProperties: false
        }
    },
    validationLevel: "strict",
    validationAction: "error"
});

// Índices para consultas del dashboard de auditoría
db.audit_traces.createIndex(
    { tenantId: 1, timestamp: -1 },
    { name: "idx_audit_tenant_timestamp" }
);

db.audit_traces.createIndex(
    { userId: 1, timestamp: -1 },
    { name: "idx_audit_user_timestamp",
      partialFilterExpression: { userId: { $type: "string" } } }
);

db.audit_traces.createIndex(
    { correlationId: 1 },
    { name: "idx_audit_correlation_id" }
);

db.audit_traces.createIndex(
    { eventType: 1, timestamp: -1 },
    { name: "idx_audit_event_type_timestamp" }
);

db.audit_traces.createIndex(
    { sagaId: 1 },
    { name: "idx_audit_saga_id",
      partialFilterExpression: { sagaId: { $type: "string" } } }
);

// traceId debe ser único para garantizar idempotencia en la inserción
db.audit_traces.createIndex(
    { traceId: 1 },
    { name: "idx_audit_trace_id", unique: true }
);
