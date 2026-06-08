# Architectural Decision Context (ADC)

**Proyecto:** PagoFacil — Billetera Digital  
**Versión del ADC:** 1.0  
**Fecha:** 2026-06-08  
**Autor(es):** AndersonElit

---

## 1. Identificación

- **Proyecto:** PagoFacil — Billetera Digital fintech multitenancy
- **Versión del ADC:** 1.0
- **Fecha:** 2026-06-08
- **Autor(es):** AndersonElit

---

## 2. Contexto Tecnológico *

### Stack permitido / mandatorio

| Capa | Tecnología / Herramienta | Estado | Justificación |
|------|--------------------------|--------|---------------|
| Lenguaje backend | Java 21 (Spring Boot 3 WebFlux — reactivo) | Mandatorio | Soporte nativo a R2DBC reactivo, virtual threads, ecosistema Spring Security OAuth2; scaffolding en `maven_hexagonal_scaffold.py` |
| Lenguaje backend ETL | Scala 3 + Apache Spark (Batch jobs K8s CronJob) | Mandatorio | Pipeline de reportería ETL; scaffolding en `scala_hexagonal_scaffold.py` |
| Lenguaje integración | Java 21 (Apache Camel 4, Spring Boot) | Mandatorio | Capa de integración con sistemas externos (ACL / EIP); scaffolding en `integration_service_scaffold.py` |
| Lenguaje frontend | TypeScript + Next.js 14 (App Router) | Mandatorio | Scaffolding en `nextjs_feature_scaffold.py`; SSR + RSC nativos |
| Base de datos relacional | PostgreSQL 16 | Mandatorio | Write model (comando CQRS) y Read model (ADR-002); Liquibase para migraciones; módulo Terraform `rds` |
| Base de datos no relacional | MongoDB 7 | Permitido | Logs de auditoría inmutables (append-only); `init-databases.sh` lo provisiona como `<prefix>_audit` |
| Mensajería / eventos | Apache Kafka 3 (KRaft, sin ZooKeeper) | Mandatorio | Bus de eventos de dominio, Transactional Outbox, pipeline ETL (`report.extracted` / `report.processed`); VPS systemd en dev, MSK en prod |
| Autenticación / identidad | AWS Cognito + OAuth 2.0 / OIDC | Mandatorio | User Pool + App Client; JWT authorizer en API Gateway; módulo Terraform `cognito` |
| API Gateway | AWS API Gateway v2 (HTTP API) | Mandatorio | Entrada pública; JWT authorizer Cognito; módulo Terraform `api-gateway` |
| Gestión de secretos | AWS Secrets Manager (floci en dev) | Mandatorio | `create-all-secrets-dev.sh`; sin secretos en texto plano ni en repositorio |
| Orquestación de contenedores | Kubernetes — K3s en VPS (dev) / EKS (staging-prod) | Mandatorio | HPA nativo; ArgoCD GitOps; `base-infrastructure-builder.sh` provisiona K3s |
| IaC | Terraform (módulos `eks`, `rds`, `cognito`, `api-gateway`, `secrets-manager`, `ecr`, `jenkins`, `msk`, `argocd`, `reporting-lambdas`) | Mandatorio | Dev con floci/LocalStack; staging-prod con AWS real |
| CI/CD | Jenkins (controller VPS/EC2 + agentes K8s) + ArgoCD (GitOps) | Mandatorio | `setup-cicd-pipeline.sh`; JCasC + Kubernetes plugin; imagen push a Gitea Package Registry (dev) / ECR (prod) |
| Calidad de código | SonarQube (VPS systemd) | Mandatorio | Integrado en pipeline Jenkins; token en `.sonar-env` |
| Source control | Gitea (VPS systemd, org por proyecto) | Mandatorio | Package Registry OCI nativo (reemplaza ECR en dev); `base-infrastructure-builder.sh` crea la org |
| Monitoreo / observabilidad | Prometheus + Grafana + Jaeger + Fluent Bit + OpenTelemetry Collector | Mandatorio | `setup-observability.sh` los instala vía Helm en K3s; trazas distribuidas obligatorias (RNF-009) |
| Saga / transacciones distribuidas | Narayana LRA Coordinator (VPS systemd, puerto 50000) | Mandatorio | Patrón orquestación LRA para flujos cross-service; `base-infrastructure-builder.sh` lo verifica |
| Pruebas de contrato | WireMock (VPS systemd, puerto 9999) | Mandatorio | Stubs de sistemas externos para pruebas de integración aisladas |
| Reportería serverless | AWS Lambda (Python) + EventBridge (floci en dev) | Mandatorio | Capa de formato PDF/XLS/CSV; módulo Terraform `reporting-lambdas`; `report_lambdas_scaffold.py` |

### Stack excluido

| Tecnología | Motivo de exclusión |
|------------|---------------------|
| Arquitectura monolítica | Restricción técnica explícita del SRS (sección 8) |
| Flyway | Incompatible con R2DBC reactivo; se usa Liquibase standalone (`run-liquibase-migrations.sh`) |
| ZooKeeper | Kafka corre en modo KRaft; no se requiere coordinador externo |
| Esquemas de autenticación propietarios | SRS RNF-005 exige OAuth 2.0 / OIDC estándar |
| Infraestructura on-premise | SRS sección 8 lo excluye explícitamente en esta fase |
| Integración directa con redes de tarjetas (Visa/Mastercard) | Fuera del alcance de esta versión (SRS sección 1) |
| Aplicaciones móviles nativas | Fuera del alcance de esta versión (SRS sección 1) |
| Productos de crédito o préstamos | Fuera del alcance de esta versión (SRS sección 1) |
| Soporte multimoneda | Fuera del alcance de esta versión (SRS sección 1) |

---

## 3. Infraestructura y Despliegue *

- **Modelo de despliegue:** Cloud (AWS) con VPS Ubuntu 26.04 LTS para el entorno de desarrollo
- **Cloud provider:** AWS (EKS, RDS, MSK, Cognito, API Gateway, Secrets Manager, ECR, EventBridge, Lambda, S3)
- **Emulación local dev:** LocalStack/floci en VPS (puerto 4566); emula los servicios AWS para el ciclo dev sin costo
- **Región / residencia de datos:** us-east-1 (configurable por tenant para requisitos regulatorios locales)
- **Modelo de servicio:** SaaS multitenancy con aislamiento de datos y configuración por tenant
- **Entornos requeridos:** desarrollo (K3s en VPS + floci), staging (EKS + AWS real), producción (EKS + AWS real), DR
- **Estrategia de contenedores:** Docker + Kubernetes (K3s en dev vía `base-infrastructure-builder.sh`; EKS en staging/prod vía Terraform)
- **Registry de imágenes:** Gitea Package Registry OCI (dev, VPS) / Amazon ECR (staging/prod)
- **GitOps:** ArgoCD instalado en el cluster K3s/EKS; pipeline Jenkins construye imagen → push registry → bump imageTag → ArgoCD sync
- **Gestión de infraestructura VPS:** `vps-setup.sh` instala servicios systemd (MongoDB, Kafka, Gitea, Jenkins, SonarQube, Narayana LRA, WireMock); `base-infrastructure-builder.sh` provisiona la capa Terraform y K3s

---

## 4. Estilo Arquitectónico Preferido *

- **Estilo principal:** Microservicios (restricción mandatoria — SRS sección 8)
- **Justificación:** Escalabilidad horizontal independiente por servicio (RNF-006), despliegue independiente (RNF-012), aislamiento de dominio por bounded context, soporte multitenancy (RNF-011)
- **Patrón de integración entre componentes:** Mixto — REST síncrono (operaciones que requieren respuesta inmediata) + Kafka asíncrono (eventos de dominio, consistencia eventual)
- **Patrón de acceso a datos:** CQRS + Transactional Outbox
- **BD de escritura (command):** PostgreSQL 16 normalizado — operaciones financieras con garantías ACID (RNF-007)
- **BD de lectura (read model):** PostgreSQL 16 desnormalizado — base de datos `pagofacil_readmodel` (ADR-002: override de MongoDB original del Strategic Design, motivado por simplificación operativa y compatibilidad con SparkJdbcSourceAdapter para ETL de reportería)
- **Sincronización write → read:** Transactional Outbox + Kafka + projection-service (consumidor Kafka que materializa el read model)
- **Reportería:** MS1 (Spark) lee el read model vía JDBC (SparkJdbcSourceAdapter, no Spark-MongoDB); MS2 (Spark) transforma; capa Lambda genera formatos

---

## 5. Atributos de Calidad y SLAs *

| Atributo | Meta | Prioridad |
|----------|------|-----------|
| Disponibilidad | 99.9% mensual (< 44 min downtime/mes) | Alta |
| Latencia máxima (p95) — consultas | < 500 ms (saldo, historial) | Alta |
| Latencia máxima (p95) — operaciones financieras | < 2 s (transferencia, depósito, retiro) | Alta |
| Throughput esperado | 1 000 req/seg en carga nominal | Media |
| Usuarios concurrentes pico | Por definir antes del diseño técnico de pruebas de carga | Media |
| RTO (Recovery Time Objective) | < 1 hora ante fallo de componente crítico | Alta |
| RPO (Recovery Point Objective) | < 15 minutos | Alta |
| Tiempo de build/deploy máximo | < 15 min pipeline Jenkins completo (build + test + push + sync ArgoCD) | Media |

---

## 6. Escala y Crecimiento

- **Usuarios activos esperados — lanzamiento:** Por definir por el Oficial de Cumplimiento y el Sponsor
- **Usuarios activos esperados — año 1:** Por definir (baseline para pruebas de carga — supuesto del SRS)
- **Usuarios activos esperados — año 3:** Por definir
- **Volumen de datos estimado — año 1:** Por definir (referencia: reportería ETL diseñada para procesar lotes de 1M+ filas)
- **Pico de carga estacional o eventos especiales:** Cierres de mes (acreditación masiva), campañas comerciales de tenants
- **¿Es un MVP o sistema de producción a escala?** Sistema de producción a escala — el SRS define SLAs de disponibilidad 99.9% y el diseño soporta 10x el volumen transaccional base sin rediseño (RNF-006)

---

## 7. Compliance y Regulaciones *

| Regulación / Estándar | Aplicable | Notas |
|-----------------------|-----------|-------|
| GDPR | Por verificar | Aplica si hay usuarios en la UE; el diseño debe facilitar derecho al olvido para datos no financieros (RNF-010) |
| HIPAA | No | No aplica — no es plataforma de salud |
| PCI-DSS | Por verificar | Aplica si se procesan datos de tarjetas en fases futuras; excluido del alcance actual |
| SOC 2 | Por verificar | Relevante para clientes enterprise (tenants financieros) |
| ISO 27001 | Por verificar | Marco de referencia para el modelo de seguridad |
| Normativas KYC/AML locales | Sí | Definidas por el Oficial de Cumplimiento antes del desarrollo del módulo compliance (supuesto SRS sección 9); incluye OFAC, ONU, listas locales |
| Normativa de protección de datos personales local | Sí | Períodos de retención de datos financieros (RN-007); derecho al olvido para PII no financiero |

- **Requisitos de retención de datos:** Datos financieros conservados el período mínimo exigido por la normativa regulatoria aplicable (RN-007); no pueden eliminarse antes de cumplido dicho período
- **Requisitos de auditoría obligatoria:** Trazas inmutables de todos los eventos de negocio con actor, acción, timestamp, IP de origen y correlationId (RF-027); registros no editables ni eliminables desde la interfaz (RF-026)
- **Restricciones de exportación de datos:** Residencia de datos por tenant sujeta a regulación local; configuración de región por tenant habilitada desde el diseño multitenancy

---

## 8. Integraciones y Sistemas Existentes

### Sistemas legados

| Sistema | Tipo | Forma de integración | Estado |
|---------|------|----------------------|--------|
| Ninguno | — | — | — |

### APIs y servicios de terceros ya definidos

| Servicio / Sistema externo | Proveedor | Propósito | Protocolo | Dirección | SLA / Latencia | Criticidad |
|----------|-----------|-----------|-----------|-----------|----------------|------------|
| Proveedor validación KYC | Por definir (SRS §9) | Verificación de documentos e identidad biométrica en onboarding | REST / webhook | Bidireccional | Por definir (contrato pendiente) | Alta |
| Entidades financieras | Múltiples (SRS §9) | Notificación de depósitos, confirmación de retiros, liquidación | REST + webhook firmado | Bidireccional | Por definir por entidad | Alta |
| Pasarelas de pago | Múltiples (SRS §9) | Procesamiento de depósitos; notificaciones de pago con firma digital | REST + webhook | Entrante | Por definir por pasarela | Alta |
| Proveedor listas AML | Por definir (OFAC, ONU, locales) | Validación contra listas de sanciones en onboarding y operaciones | REST (tiempo real) o file (batch) | Saliente (consumo) | p95 < 800 ms / 99.5% | Alta |
| Proveedor SMS / Email | Por definir (SRS §9) | Notificaciones MFA, confirmación de operaciones, alertas | REST (SMTP para email, HTTP para SMS) | Saliente | p95 < 2 s | Media |

### Dependencias de datos

- **Fuentes de datos externas:** Listas AML/sanciones (OFAC, ONU, locales); confirmaciones de depósito/retiro desde entidades financieras y pasarelas
- **Sistemas que consumen datos de este sistema:** Entidades financieras aliadas vía API (RF-023); canales de distribución externos (apps móviles de terceros) vía API REST

### Capa de integración (Apache Camel)

- **¿Centralizar la conectividad con sistemas externos en un microservicio dedicado `integration-service`?** Sí
- **Justificación:** Gobierno central de credenciales y SLAs de terceros (KYC, AML, entidades financieras, pasarelas); dominio limpio sin acoplamientos externos en los servicios de negocio; orquestación de sagas LRA centralizada; `integration_service_scaffold.py` genera el scaffolding
- **Protocolos de entrada no-HTTP a soportar:** Ninguno en esta fase (todos los externos son REST/webhook)

### Estrategia de transacciones distribuidas (Saga)

- **¿Hay transacciones que cruzan servicios?** Sí — depósito, transferencia y retiro involucran identity-service, wallet-service, fraud-service, notification-service y entidades externas
- **Estilo de saga preferido:** Orquestación
- **Ubicación del orquestador:** `integration-service` (Apache Camel + Narayana LRA)
- **Coordinador de transacciones:** Narayana LRA (VPS puerto 50000 en dev; contenedor en K8s en staging/prod)

| Flujo transaccional | Servicios participantes | Paso(s) que requieren compensación | Criticidad |
|---------------------|-------------------------|-------------------------------------|------------|
| Depósito de fondos | integration-service → wallet-service → notification-service → entidad financiera | Reversión de acreditación si la confirmación externa falla | Alta |
| Transferencia entre usuarios | integration-service → wallet-service (débito emisor) → wallet-service (crédito receptor) → fraud-service → notification-service | Reversión del débito del emisor si el crédito falla | Alta |
| Retiro de fondos | integration-service → wallet-service (reserva) → entidad financiera → wallet-service (confirmar/liberar) → notification-service | Liberación de la reserva si la entidad financiera reporta fallo | Alta |

---

## 9. Equipo y Capacidad

- **Tamaño del equipo de desarrollo:** Por definir por el Sponsor y Project Manager
- **Perfil dominante:** Mixto (supuesto: equipo con experiencia en microservicios y seguridad financiera — SRS §9)
- **Experiencia con el estilo arquitectónico elegido:** Alta (supuesto del SRS §9: equipo con experiencia en microservicios, CQRS, Saga, seguridad en aplicaciones financieras)
- **Velocidad de entrega esperada:** Por definir; plan de desarrollo generado con 6 etapas (infra → microservicios → frontend → serverless)
- **¿Hay equipos externos / outsourcing?** Por definir

---

## 10. Presupuesto de Infraestructura

- **Presupuesto mensual de infraestructura (cloud/servidores):** Por definir por el Sponsor
- **¿Existe presupuesto para licencias de software comercial?** No — el stack completo usa herramientas open-source (Spring Boot, Kafka, PostgreSQL, MongoDB, Prometheus, Grafana, Jaeger, Jenkins, ArgoCD, SonarQube Community, K3s, Narayana, WireMock); los servicios AWS son pay-per-use
- **Restricciones de costo que afecten decisiones de diseño:** Dev usa LocalStack/floci en VPS para emular AWS sin costo; los recursos AWS (EKS, RDS, MSK) solo se provisionen en staging/prod

---

## 11. Restricciones Organizacionales

- El sistema **debe** implementarse como microservicios en Kubernetes. Arquitectura monolítica prohibida (SRS §8).
- Todas las APIs externas **deben** usar OAuth 2.0 / OIDC. Esquemas propietarios no permitidos (SRS §8, RNF-005).
- TLS 1.2 o superior es **obligatorio** en toda comunicación, interna y externa (SRS §8, RNF-003).
- Los secretos, claves y tokens **no pueden** almacenarse en código fuente, repositorios sin cifrar ni variables de entorno en texto plano (SRS §8, RN-008).
- Las migraciones de esquema las ejecuta **Liquibase standalone** (`run-liquibase-migrations.sh`) previo al despliegue; no Flyway ni migraciones embebidas en el JAR (incompatible con R2DBC).
- El Read Model CQRS es **PostgreSQL** (base `pagofacil_readmodel`) — ADR-002 override definitivo sobre MongoDB del Strategic Design; MS1 Spark lee vía JDBC.
- La capa de integración con sistemas externos **reside en `integration-service`** (Apache Camel); los servicios de dominio no tienen acoplamiento directo con terceros.

---

## 12. Decisiones Previas Ya Tomadas

| Decisión | Resultado | Quién decidió | Fecha |
|----------|-----------|---------------|-------|
| Estilo arquitectónico | Microservicios en Kubernetes (mandatorio) | SRS — stakeholders | 2026-06-08 |
| Arquitectura de acceso a datos | CQRS + Transactional Outbox + Kafka | Technical Design SDD | 2026-06-06 |
| BD de escritura | PostgreSQL 16 (garantías ACID para operaciones financieras) | Technical Design SDD | 2026-06-06 |
| BD de lectura (Read Model) — ADR-002 | PostgreSQL 16 desnormalizado (`pagofacil_readmodel`) — override de MongoDB del Strategic Design | Technical Design SDD | 2026-06-06 |
| Framework backend | Spring Boot 3 WebFlux (reactivo, R2DBC) — Java 21 | Technical Design SDD | 2026-06-06 |
| Framework frontend | Next.js 14 (App Router, TypeScript) | Technical Design SDD | 2026-06-06 |
| Mensajería | Apache Kafka 3 KRaft (sin ZooKeeper) | Technical Design SDD | 2026-06-06 |
| Gestión de identidad / autenticación | AWS Cognito + OAuth 2.0 / OIDC + JWT | Technical Design SDD | 2026-06-06 |
| Saga / transacciones distribuidas | Orquestación con Narayana LRA en `integration-service` | Technical Design SDD | 2026-06-06 |
| Capa de integración externa | Apache Camel 4 en `integration-service` dedicado | Technical Design SDD | 2026-06-06 |
| Migraciones de esquema | Liquibase standalone (incompatibilidad Flyway/R2DBC) | Technical Design SDD | 2026-06-06 |
| Registry de imágenes (dev) | Gitea Package Registry OCI (reemplaza ECR en dev) | `base-infrastructure-builder.sh` | 2026-06-06 |
| Orquestador K8s (dev) | K3s nativo en VPS (reemplaza K3d/EKS emulado) | `base-infrastructure-builder.sh` | 2026-06-06 |
| Observabilidad | OpenTelemetry + Prometheus + Grafana + Jaeger + Fluent Bit | `setup-observability.sh` | 2026-06-06 |

---

## 13. Reportería

- **¿El sistema requiere generación de reportes?** Sí — RF-022 (ROS/SAR regulatorio), RF-028 (reportes regulatorios periódicos), RF-026 (dashboard de auditoría con exportación)
- **Fuente de datos del ETL:** Read model CQRS — PostgreSQL (`pagofacil_readmodel`) vía JDBC (ADR-002; MS1 usa SparkJdbcSourceAdapter, no Spark-MongoDB)
- **Disparo del ETL:** Ambos — programado/schedule (reportes regulatorios periódicos) y on-demand por evento de comando (ROS/SAR ante alerta AML/fraude)
- **Persistencia del catálogo de esquemas:** Tabla `report_schema_catalog` en BD

### Tipos de reporte

| Tipo de reporte (`reportType`) | Fuente (tabla/vista — read model) | Columnas/esquema esperado | Formatos de salida | Frecuencia / disparo | Volumetría estimada |
|---|---|---|---|---|---|
| `volumen-transaccional` | `rm_transactions` | fecha, tenant_id, tipo_operacion, cantidad, monto_total | PDF / XLS / CSV | Mensual programado | Por definir |
| `operaciones-bloqueadas` | `rm_transactions`, `rm_compliance_alerts` | fecha, operacion_id, motivo_bloqueo, usuario_id, monto | PDF / XLS | Mensual programado / on-demand | Por definir |
| `alertas-aml` | `rm_compliance_alerts` | fecha, alerta_id, usuario_id, regla_disparada, nivel_riesgo, estado | PDF / XLS / CSV | Mensual programado / on-demand | Por definir |
| `kyc-por-periodo` | `rm_users` | periodo, total_registros, aprobados, rechazados, pendientes, suspendidos_aml | PDF / XLS | Mensual programado | Por definir |
| `sar-ros` | `rm_transactions`, `rm_compliance_alerts` | operacion_id, usuario_id, monto, descripcion, regla_aml, timestamp | PDF (formato normativo) | On-demand por evento AML/fraude | Por definir |

---

## 14. Información Adicional

- **Multitenancy:** Aislamiento por `tenant_id` en todas las entidades del modelo de datos y en la configuración de servicios. Todos los bounded contexts deben propagar el `tenant_id` desde la capa de autenticación (claims JWT Cognito) sin excepción (RNF-011).
- **Idempotencia transaccional:** Todas las APIs de operaciones financieras aceptan y respetan el header `Idempotency-Key` (UUID v4); el sistema garantiza procesamiento único ante reintentos (RF-016, RNF-013, RN-003).
- **Consistencia financiera:** Operaciones de modificación de saldo con garantías ACID en PostgreSQL (RNF-007); saldo nunca negativo (RN-002); operaciones confirmadas no reversibles unilateralmente (RN-004).
- **Cifrado:** AES-256 para datos en reposo sensibles (PII, credenciales, datos financieros); claves gestionadas en AWS Secrets Manager con rotación automática (RNF-004).
- **Arquitectura hexagonal:** Todos los microservicios backend siguen arquitectura hexagonal (puertos y adaptadores) generada por `maven_hexagonal_scaffold.py`; separación estricta entre dominio, aplicación e infraestructura.
- **Plan de desarrollo generado:** 19 documentos en `docs/development/` cubren el roadmap de 6 etapas (infra → BDs → scaffold → CI/CD → microservicios → frontend → serverless). Orden de implementación: identity → wallet → fraud → notification → projection → audit → integration → MS1 → MS2 → frontend → serverless.
- **Invocación de la skill `/strategic-design-sdd`:**

```
/strategic-design-sdd docs/requirements/SRS-PagoFacil.md docs/planning/ADC-PagoFacil.md
```

---

*Documento generado como parte de la etapa de Planeación del SDLC — complementa el PID y sirve de entrada al Strategic Design (SDD). El stack tecnológico está soportado integralmente por los scripts en `.claude/scripts/` y los templates en `.claude/templates/`.*
