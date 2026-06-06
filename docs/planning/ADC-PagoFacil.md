# Architectural Decision Context (ADC)

**Proyecto:** PagoFacil — Billetera Digital  
**Versión del ADC:** 1.0  
**Fecha:** 2026-06-06  
**Autor(es):** AndersonElit

---

## 1. Identificación

- **Proyecto:** PagoFacil — Billetera Digital
- **Versión del ADC:** 1.0
- **Fecha:** 2026-06-06
- **Autor(es):** AndersonElit

---

## 2. Contexto Tecnológico *

### Stack permitido / mandatorio

| Capa | Tecnología / Herramienta | Estado | Justificación |
|------|--------------------------|--------|---------------|
| Lenguaje backend (servicios de dominio) | Java 21 + Spring Boot 3.4.1 (WebFlux reactivo) | Mandatorio | Template `maven_hexagonal_scaffold.py` genera proyectos Spring Boot 3.4.1 con Java 21 y stack reactivo (R2DBC / WebFlux); todas las dependencias del BOM están fijadas a esta versión. |
| Lenguaje backend (ETL / reportería) | Scala 2.13 + Apache Spark 3.5.1 | Mandatorio | Template `scala_hexagonal_scaffold.py` genera los microservicios de extracción y procesamiento del subsistema de reportería (batch Spark + sbt 1.9.8). |
| Lenguaje de integración | Java 21 + Apache Camel 4.10.2 + Spring Boot 3.4.1 | Mandatorio | Template `integration_service_scaffold.py` genera el `integration-service` con Camel 4.10.2 (BOM) sobre Spring Boot 3.4.1; incluye el orquestador de saga Narayana LRA. |
| Lenguaje frontend | TypeScript 5 + Next.js 15.3 + React 19 | Mandatorio | Template `nextjs_feature_scaffold.py` genera el proyecto frontend con Next.js 15.3, React 19 y TypeScript 5; arquitectura Feature-Based enterprise. |
| Base de datos relacional | PostgreSQL 16.3 (AWS RDS en staging/prod; Docker `postgres:16-alpine` en dev) | Mandatorio | Módulo Terraform `rds` fija `engine_version = "16.3"`. Migraciones gestionadas por Flyway (script `scaffold-all-services.sh`). |
| Base de datos no relacional | MongoDB 7 (EC2 + EBS en staging/prod; Docker `mongo:7` en dev) | Mandatorio | Script `base-infrastructure-builder.sh` levanta `mongo:7`; módulo Terraform `mongodb` usa imagen 7.0. Rol: read model CQRS y auditoría. |
| Mensajería / eventos | Apache Kafka 3.7.0 (AWS MSK en staging/prod; Docker `apache/kafka:3.7.0` KRaft en dev) | Mandatorio | Script levanta Kafka en modo KRaft sin ZooKeeper. Módulo Terraform `msk` para staging/prod. Topics `report.extracted` y `report.processed` provisionados automáticamente. |
| Capa de integración / saga | Apache Camel 4.10.2 + Narayana LRA (coordinador de saga) | Mandatorio | `integration-service` centraliza rutas Camel y el orquestador Saga EIP/LRA. WireMock 3.9.1 para contract tests de rutas de salida. |
| Autenticación / identidad | AWS Cognito (User Pool + JWT) — OAuth 2.0 / OpenID Connect | Mandatorio | Módulo Terraform `cognito` provisiona User Pool y App Client con tokens JWT. API Gateway valida tokens vía authorizer JWT. MFA desactivado en dev, OPTIONAL en staging/prod. |
| API Gateway | AWS API Gateway v2 (HTTP) | Mandatorio | Módulo Terraform `api-gateway` crea la API HTTP con authorizer Cognito JWT y stage `$default` con autodeploy. |
| Gestión de secretos | AWS Secrets Manager | Mandatorio | Módulo `secrets-manager` y script `create-all-secrets-dev.sh`. Prohibido texto plano; los servicios leen secretos en startup vía `spring-cloud-aws-secretsmanager`. |
| Contenedores | Docker + Kubernetes (K3d en dev, AWS EKS en staging/prod) | Mandatorio | Script `base-infrastructure-builder.sh` provisiona cluster K3d con registry propio (`:5100`). Módulo Terraform `eks` para staging/prod. |
| Registro de imágenes | AWS ECR | Mandatorio | Módulo Terraform `ecr` crea un repositorio por microservicio. K3d registry `k3d-<proyecto>-registry:5100` para dev local. |
| CI/CD | Jenkins (controller EC2 + agentes en pods EKS) + ArgoCD (GitOps) | Mandatorio | Módulo Terraform `jenkins` y `argocd`. Módulo `jenkins-shared-library-builder.sh` configura la shared library. Gitea 1.22 como servidor Git interno para los repositorios de microservicios. |
| Infraestructura como código | Terraform ≥ 1.6.0 (Floci en dev; AWS real en staging/prod) | Mandatorio | Estructura `terraform/backend` (módulos: eks, rds, iam, cognito, api-gateway, secrets-manager, ecr, mongodb, jenkins, msk, argocd, reporting-lambdas) y `terraform/frontend` (módulo vercel-project). |
| Frontend hosting | Vercel (provider Terraform `vercel/vercel ~> 2.0`) | Mandatorio | Módulo Terraform `vercel-project` provisiona el proyecto; `vercel.json` deshabilita despliegues automáticos de Git; Jenkins es el único disparador. |
| Calidad de código | SonarQube LTS Community | Mandatorio | Script `base-infrastructure-builder.sh` levanta SonarQube en el stack de dev; pipeline Jenkins ejecuta `mvn sonar:sonar` como quality gate. |
| Monitoreo / observabilidad | OpenTelemetry + Prometheus + AWS CloudWatch | Mandatorio | SRS RNF-007: logging estructurado JSON con correlationId, métricas Prometheus, trazas distribuidas OpenTelemetry. CloudWatch para logs de MongoDB y Jenkins en staging/prod. |
| Reportería serverless | AWS Lambda + AWS EventBridge | Mandatorio | Template `report_lambdas_scaffold.py` genera las lambdas de formato (PDF/XLS/CSV). Script provisiona bus EventBridge `<proyecto>-report-bus` y bucket S3 `<proyecto>-reports`. |
| Testing de contratos | WireMock 3.9.1 | Mandatorio | Script levanta WireMock para simular sistemas externos en integration tests de las rutas Camel. |
| Frontend: state management | Zustand 5.0 | Mandatorio | Incluido en `package.json` del template Next.js. |
| Frontend: data fetching | TanStack Query v5 | Mandatorio | Incluido en `package.json` del template Next.js. |
| Frontend: validación de formularios | React Hook Form 7 + Zod 3 | Mandatorio | Incluido en `package.json` del template Next.js. |
| Frontend: testing | Vitest 2 + Playwright 1.49 | Mandatorio | Incluido en `package.json` del template Next.js. |

### Stack excluido

| Tecnología | Motivo de exclusión |
|------------|---------------------|
| Apps móviles nativas (iOS / Android) | Fuera del alcance del SRS. El acceso móvil se realiza mediante las APIs REST expuestas. |
| Integración directa con redes de tarjetas (Visa / Mastercard) | Explícitamente excluido en SRS §8. |
| Soporte multimoneda | Fuera del alcance de la fase actual (SRS §1). |
| ZooKeeper | Sustituido por Kafka en modo KRaft. |
| Variables de entorno no cifradas para credenciales | Prohibido por RNF-003 y RN-010. Todas las credenciales van a Secrets Manager. |
| Esquemas de autenticación propietarios para APIs externas | Prohibido por RNF-004. Solo OAuth 2.0 / OpenID Connect. |
| Almacenamiento de contraseñas en texto plano o hash reversible | Prohibido por RN-010. |

---

## 3. Infraestructura y Despliegue *

- **Modelo de despliegue:** Cloud (AWS)
- **Cloud provider:** AWS
- **Región / residencia de datos:** `us-east-1` (fijada en todos los módulos Terraform y configuraciones de Spring Cloud AWS)
- **Modelo de servicio:** SaaS — plataforma multitenancy (RF-020)
- **Entornos requeridos:** desarrollo (dev con Floci + K3d), staging (AWS real), producción (AWS real); DR implícito en RTO/RPO del SRS
- **Estrategia de contenedores:** Docker + Kubernetes (K3d en dev, EKS en staging/prod); despliegue GitOps con ArgoCD; imágenes construidas con Kaniko en pods EKS desde Jenkins

---

## 4. Estilo Arquitectónico Preferido *

- **Estilo principal:** Microservicios event-driven
- **Justificación:** El SRS §2 describe explícitamente "arquitectura de microservicios event-driven desplegada en contenedores (Kubernetes)". Los scripts y templates implementan este estilo: cada microservicio es un proyecto Maven/Spring Boot independiente con su propia base de datos (Database-per-Service), despliegue y escalamiento autónomos (RNF-009).
- **Patrón de integración entre componentes:** Mixto — mensajería asíncrona (Kafka, `at-least-once`) para eventos de dominio; REST/HTTP con TLS para operaciones síncronas; gRPC disponible como opción en comunicaciones inter-servicio.
- **Patrón de acceso a datos:** CQRS — escrituras en PostgreSQL (operaciones financieras con garantías ACID); lecturas en MongoDB (read model desnormalizado para historial, reportería y auditoría).
- **BD de escritura (command):** PostgreSQL 16.3 — datos operacionales normalizados, transacciones ACID, migraciones Flyway.
- **BD de lectura (query/read model):** MongoDB 7 — documentos desnormalizados para consultas de historial, dashboard de auditoría y fuente del ETL de reportería.
- **Sincronización command → query:** Transactional Outbox Pattern (RNF-005) + Kafka (`at-least-once`); los consumidores implementan idempotencia (RF-011, RNF-008).

---

## 5. Atributos de Calidad y SLAs *

| Atributo | Meta | Prioridad |
|----------|------|-----------|
| Disponibilidad | ≥ 99.9% mensual (≤ 43.8 min downtime no planificado/mes) | Alta |
| Latencia máxima (p95) — consultas (saldo, historial) | < 500 ms bajo carga nominal | Alta |
| Latencia máxima (p95) — operaciones financieras (validación + encolamiento) | < 2 000 ms bajo carga nominal | Alta |
| Throughput esperado | Por definir en pruebas de carga pre-producción; diseño soporte ≥ 10x volumen inicial sin rediseño (RNF-006) | Alta |
| Usuarios concurrentes pico | Por definir (ver sección 6) | Media |
| RTO (Recovery Time Objective) | < 1 hora | Alta |
| RPO (Recovery Point Objective) | < 15 minutos | Alta |
| Tiempo de build/deploy máximo | Por definir; SonarQube quality gate requerido antes del merge | Media |
| Cobertura de pruebas automatizadas (módulos financieros y seguridad) | ≥ 80% | Alta |

---

## 6. Escala y Crecimiento

- **Usuarios activos esperados — lanzamiento:** Por definir (referencia PID)
- **Usuarios activos esperados — año 1:** Por definir
- **Usuarios activos esperados — año 3:** Por definir
- **Volumen de datos estimado — año 1:** Por definir; retención mínima de transacciones y auditoría: 5 años (RN-012)
- **Pico de carga estacional o eventos especiales:** A definir con el equipo de negocio (quincenas de pago, días de mercado, campañas)
- **¿Es un MVP o sistema de producción a escala?** Sistema de producción a escala — los SLAs de disponibilidad (99.9%) y los requisitos regulatorios (KYC/AML, PCI-DSS) excluyen un enfoque MVP informal

---

## 7. Compliance y Regulaciones *

| Regulación / Estándar | Aplicable | Notas |
|-----------------------|-----------|-------|
| GDPR | Sí (u equivalente local) | SRS RNF-010: cumplimiento con legislación de protección de datos personales vigente en la jurisdicción de operación. Retención de registros de auditoría inmutables por período legalmente requerido. |
| HIPAA | No | No aplica al dominio fintech de pagos. |
| PCI-DSS | Por verificar | El sistema no procesa datos de tarjeta directamente (excluye integración con redes Visa/Mastercard en esta fase), pero maneja datos financieros sensibles. El oficial de compliance debe confirmar el nivel de aplicabilidad antes del diseño técnico. |
| SOC 2 | Por verificar | Recomendado para un SaaS financiero; pendiente de decisión organizacional. |
| ISO 27001 | Por verificar | Alineado con los controles de seguridad del SRS; formalización pendiente. |
| Normativas locales (KYC / AML) | Sí — Mandatorio | RF-002, RF-014, RF-015: KYC como prerequisito de activación, controles AML, verificación contra listas OFAC/ONU, generación de ROS en formato regulatorio. El marco KYC/AML debe ser definido por el oficial de compliance antes del inicio de la implementación (supuesto del SRS §9). |

- **Requisitos de retención de datos:** Mínimo 5 años para registros de transacciones y auditoría (RN-012); el período exacto lo define el oficial de compliance según normativa aplicable.
- **Requisitos de auditoría obligatoria:** Registros inmutables de todas las operaciones financieras (RN-005); log de decisiones de fraude y AML (RF-014, RF-015, RF-016); trazabilidad completa con correlationId (RF-010, RNF-007). Pentest externo sin vulnerabilidades críticas/altas antes del despliegue productivo (RNF-003).
- **Restricciones de exportación de datos:** Datos residentes en `us-east-1`; exportación de datos personales sujeta a normativa GDPR/equivalente local. Los reportes AML deben exportarse en formato exigido por la normativa aplicable (RF-015).

---

## 8. Integraciones y Sistemas Existentes

### Sistemas legados

| Sistema | Tipo | Forma de integración | Estado |
|---------|------|----------------------|--------|
| — | — | — | No existen sistemas legados identificados en esta fase. El SRS indica que la organización carece de plataforma propia de pagos. |

### APIs y servicios de terceros ya definidos

| Servicio / Sistema externo | Proveedor | Propósito | Protocolo | Dirección | SLA / Latencia | Criticidad |
|----------|-----------|-----------|-----------|-----------|----------------|------------|
| Entidades financieras / Pasarelas de pago | Por definir (contratos pendientes de firma — SRS §9) | Fondeo, liquidación y confirmación de depósitos y retiros (RF-006, RF-007, RF-018) | REST | Saliente + Entrante (webhook de confirmación) | Por definir en contratos de servicio | Alta |
| Proveedor KYC | Por definir | Validación documental y/o biométrica para onboarding (RF-002) | REST | Saliente | Por definir | Alta |
| Listas de sanciones AML (OFAC, ONU, etc.) | Por definir | Verificación de usuarios y contrapartes contra listas activas (RF-015) | REST / file | Saliente | Por definir | Alta |

### Dependencias de datos

- **Fuentes de datos externas:** Entidades financieras (confirmaciones de depósito/retiro), proveedor KYC (resultado de validación de identidad), listas de sanciones AML (actualizadas periódicamente).
- **Sistemas que consumen datos de este sistema:** Reportes regulatorios AML exportados a la autoridad competente; potenciales integraciones con sistemas de compliance de terceros a futuro.

### Capa de integración (Apache Camel)

- **¿Centralizar la conectividad con sistemas externos en un microservicio dedicado `integration-service`?** Sí
- **Justificación:** El template `integration_service_scaffold.py` implementa el `integration-service` con Apache Camel 4.10.2 como capa de integración y ACL. Centraliza gobierno de credenciales y SLAs de sistemas externos, mantiene los bounded contexts del dominio limpios y gestiona el orquestador de saga Narayana LRA para flujos transaccionales distribuidos.
- **Protocolos de entrada no-HTTP a soportar:** Webhooks entrantes de entidades financieras (HTTP callback); timer para conciliación automática (RF-012). File/FTP solo si algún proveedor AML o KYC requiere intercambio de listas por archivo (por definir).

### Estrategia de transacciones distribuidas (Saga)

- **¿Hay transacciones que cruzan servicios?** Sí — depósito, retiro y transferencia involucran múltiples servicios (billetera, fraude, notificaciones, integración con entidades financieras).
- **Estilo de saga preferido:** Orquestación (Camel Saga EIP + Narayana LRA)
- **Ubicación del orquestador:** En `integration-service` — el template `integration_service_scaffold.py` genera el orquestador LRA dentro de este servicio.
- **Coordinador de transacciones:** Narayana LRA (contenedor `quay.io/jbosstm/lra-coordinator:latest` en dev; desplegado en K8s en staging/prod)

| Flujo transaccional | Servicios participantes | Paso(s) que requieren compensación | Criticidad |
|---------------------|-------------------------|-------------------------------------|------------|
| Depósito de fondos | `integration-service`, `wallet-service`, `notification-service` | Reversión del saldo pendiente si la entidad financiera rechaza el fondeo | Alta |
| Retiro de fondos | `integration-service`, `wallet-service`, `fraud-service`, `notification-service` | Liberación de fondos reservados si la entidad financiera rechaza la instrucción de pago | Alta |
| Transferencia entre usuarios | `wallet-service` (débito + crédito atómico ACID), `fraud-service`, `notification-service` | La transferencia interna es atómica en PostgreSQL; compensación aplica si el motor de fraude retiene post-débito (escenario de retención tardía) | Alta |
| Conciliación automática | `integration-service`, `wallet-service`, `audit-service` | Registro de discrepancia y generación de alerta (RN-012 / RF-012) — no requiere rollback de saldo | Media |

---

## 9. Equipo y Capacidad

- **Tamaño del equipo de desarrollo:** Por definir
- **Perfil dominante:** Mixto — el SRS §9 asume experiencia demostrada en arquitecturas de microservicios y sistemas financieros
- **Experiencia con el estilo arquitectónico elegido:** Alta (supuesto del SRS)
- **Velocidad de entrega esperada:** Por definir en la fase de planeación de sprints; el SRS requiere auditoría externa de compliance antes del despliegue productivo
- **¿Hay equipos externos / outsourcing?** Por definir; el oficial de compliance participa como stakeholder externo en la definición del marco KYC/AML

---

## 10. Presupuesto de Infraestructura

- **Presupuesto mensual de infraestructura (cloud/servidores):** Por definir
- **¿Existe presupuesto para licencias de software comercial?** Stack completamente open-source / managed services AWS. SonarQube Community (gratuito); Vercel (plan a definir según tráfico); Narayana LRA (open-source Red Hat). No se identifican licencias comerciales obligatorias en los templates.
- **Restricciones de costo que afecten decisiones de diseño:** En dev se usa Floci (emulador AWS local) para minimizar costos cloud. EKS y MSK están deshabilitados en dev (`enabled=false`), sustituidos por K3d y Kafka Docker. MongoDB en dev es un contenedor local; el módulo Terraform `mongodb` (EC2 + EBS) solo aplica a staging/prod.

---

## 11. Restricciones Organizacionales

- Los microservicios backend deben implementarse con arquitectura hexagonal (Ports & Adapters) usando los templates Maven y Scala provistos en `.claude/templates/`. No se permiten estructuras de proyecto alternativas.
- El frontend debe desplegarse exclusivamente en Vercel; Jenkins es el único disparador de despliegues (sin despliegues automáticos de Git en `vercel.json`).
- Toda credencial, secreto y clave criptográfica debe gestionarse a través de AWS Secrets Manager. Queda prohibido el uso de variables de entorno no cifradas, texto plano o repositorios de código para almacenar secretos.
- El CI/CD debe implementarse con Jenkins (controller EC2 + agentes en pods Kubernetes) + ArgoCD (GitOps); no se permiten otras herramientas de CI/CD.
- La infraestructura debe provisionarse con Terraform ≥ 1.6.0 usando la estructura de módulos definida en `terraform/backend` y `terraform/frontend`.
- El proceso de validación de identidad (KYC) es un prerequisito no negociable para la activación de cuentas (RN-001). Esta regla no puede ser desactivada por configuración.
- Los registros de operaciones financieras son inmutables una vez creados (RN-005). No se puede implementar update o delete sobre eventos de auditoría.

---

## 12. Decisiones Previas Ya Tomadas

| Decisión | Resultado | Quién decidió | Fecha |
|----------|-----------|---------------|-------|
| Lenguaje backend (servicios de dominio) | Java 21 + Spring Boot 3.4.1 WebFlux reactivo | Equipo de arquitectura (inferido de templates) | Anterior a 2026-06-06 |
| Lenguaje backend (ETL / reportería) | Scala 2.13 + Apache Spark 3.5.1 | Equipo de arquitectura (inferido de templates) | Anterior a 2026-06-06 |
| Lenguaje de integración / saga | Java 21 + Apache Camel 4.10.2 + Narayana LRA | Equipo de arquitectura (inferido de templates) | Anterior a 2026-06-06 |
| Framework frontend | Next.js 15.3 + TypeScript 5 + React 19 | Equipo de arquitectura (inferido de templates) | Anterior a 2026-06-06 |
| Base de datos operacional | PostgreSQL 16.3 | Equipo de arquitectura (módulo Terraform `rds`) | Anterior a 2026-06-06 |
| Base de datos read model / auditoría | MongoDB 7 | Equipo de arquitectura (módulo Terraform `mongodb`) | Anterior a 2026-06-06 |
| Bus de mensajería | Apache Kafka 3.7.0 (KRaft) | Equipo de arquitectura (módulo Terraform `msk`) | Anterior a 2026-06-06 |
| Identidad y autenticación | AWS Cognito + OAuth 2.0 / OpenID Connect | Equipo de arquitectura (módulo Terraform `cognito`) | Anterior a 2026-06-06 |
| API Gateway | AWS API Gateway v2 (HTTP) con authorizer JWT Cognito | Equipo de arquitectura (módulo Terraform `api-gateway`) | Anterior a 2026-06-06 |
| Gestión de secretos | AWS Secrets Manager | Equipo de arquitectura (módulo Terraform `secrets-manager`) | Anterior a 2026-06-06 |
| Orquestación de contenedores | Kubernetes — K3d (dev) / EKS (staging/prod) | Equipo de arquitectura (scripts e infra) | Anterior a 2026-06-06 |
| GitOps | ArgoCD | Equipo de arquitectura (módulo Terraform `argocd`) | Anterior a 2026-06-06 |
| CI/CD | Jenkins + ArgoCD + Gitea (repos internos) | Equipo de arquitectura (módulo Terraform `jenkins`) | Anterior a 2026-06-06 |
| IaC | Terraform ≥ 1.6.0 | Equipo de arquitectura (estructura `terraform/`) | Anterior a 2026-06-06 |
| Hosting frontend | Vercel (Terraform provider `vercel/vercel ~> 2.0`) | Equipo de arquitectura (módulo `vercel-project`) | Anterior a 2026-06-06 |
| Calidad de código | SonarQube LTS Community | Equipo de arquitectura (script `base-infrastructure-builder.sh`) | Anterior a 2026-06-06 |
| Patrón de consistencia transaccional | Transactional Outbox Pattern + Saga (orquestación LRA) | Equipo de arquitectura (templates + scripts) | Anterior a 2026-06-06 |
| Región AWS | `us-east-1` | Equipo de arquitectura (configuraciones Terraform y Spring) | Anterior a 2026-06-06 |

---

## 13. Reportería

- **¿El sistema requiere generación de reportes?** Sí — RF-017 (reportes regulatorios exportables PDF/CSV desde dashboard de auditoría) y RF-015 (reportes AML en formato regulatorio).
- **Fuente de datos del ETL:** Read model CQRS (MongoDB 7) como fuente principal; JDBC sobre PostgreSQL como fuente alternativa cuando el read model no esté disponible.
- **Disparo del ETL:** Ambos — programado/schedule (CronJob K8s, expresión configurable, default `0 * * * *`) y on-demand por evento de comando (para reportes regulatorios bajo demanda desde el dashboard de auditoría).
- **Persistencia del catálogo de esquemas:** Tabla `report_schema_catalog` en base de datos (PostgreSQL).

### Tipos de reporte

| Tipo de reporte (`reportType`) | Fuente (colección/tabla) | Columnas/esquema esperado | Formatos de salida | Frecuencia / disparo | Volumetría estimada |
|---|---|---|---|---|---|
| `transacciones-diario` | Colección `transacciones` (read model MongoDB) | fecha, id_operacion, tipo, monto, estado, usuario_id, correlation_id | PDF / CSV | Programado diario / on-demand | Por definir según usuarios activos |
| `reporte-aml` | Colección `transacciones` + `alertas_aml` (read model MongoDB) | fecha, usuario_id, monto, tipo_operacion, resultado_aml, lista_sancion_match, estado_revision | CSV (formato regulatorio) | On-demand (auditor) | Por definir |
| `alertas-fraude` | Colección `alertas` (read model MongoDB) | fecha, id_operacion, regla_disparada, severidad, estado_revision, auditor_responsable | PDF / CSV | On-demand (auditor) | Por definir |
| `saldo-usuarios` | Colección `billeteras` (read model MongoDB) | fecha_corte, usuario_id, tenant_id, saldo_disponible, saldo_pendiente | CSV | Programado mensual | Por definir |
| `conciliacion` | Colección `conciliaciones` (read model MongoDB) | fecha, id_operacion, monto_interno, monto_externo, discrepancia, estado | PDF / CSV | Programado diario | Por definir |

---

## 14. Información Adicional

**Entorno de desarrollo local (Floci):**  
El stack de dev usa Floci (`floci/floci:latest`) como emulador de servicios AWS (S3, MSK, EKS, Secrets Manager, ECR, Cognito, API Gateway). Las limitaciones conocidas del emulador están documentadas en los módulos Terraform con flags específicos (`var.floci`, `var.emulator`, `enable_data_plane`, `enabled`). Para servicios que Floci no soporta completamente (MongoDB, Kafka), se levantan contenedores Docker reales en la red `floci-net`.

**Patrón Database-per-Service:**  
Cada microservicio tiene su propia base de datos lógica. El script `scaffold-all-services.sh` propaga los prefijos `--pg-db` y `--mongo-db` a los templates para que cada servicio derive su BD (`<prefix>_<servicio_slug>`), coherente con el script `init-databases.sh`.

**Mínimo privilegio y seguridad mTLS:**  
Las comunicaciones inter-servicios deben usar autenticación mTLS (RNF-004). AWS Cognito provee el plano de autenticación externo; el plano interno usa certificados de servicio dentro del cluster Kubernetes.

**Invocación de la skill:**

```
/strategic-design-sdd docs/requirements/SRS-PagoFacil.md docs/planning/ADC-PagoFacil.md
```
