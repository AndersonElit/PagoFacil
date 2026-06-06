# Plan de Incorporación de Observabilidad

## Objetivo

Incorporar observabilidad transversal (logs estructurados, métricas y trazas distribuidas) en el stack `.claude/` para que cualquier proyecto generado con este SDLC la incluya desde el scaffold inicial. El resultado debe funcionar en dev (K3d + floci) sin cambios y en staging/prod sobre AWS con la misma instrumentación.

---

## Stack de Observabilidad

| Pilar | Dev (K3d + floci) | Staging / Prod (EKS + AWS) |
|---|---|---|
| **Trazas** | OTEL Collector → Jaeger (all-in-one) | OTEL Collector → AWS X-Ray |
| **Métricas** | Prometheus (kube-prometheus-stack) + Grafana | Amazon Managed Prometheus (AMP) + Amazon Managed Grafana (AMG) o CloudWatch Metrics |
| **Logs** | Fluent Bit DaemonSet → Loki + Grafana | `aws-for-fluent-bit` DaemonSet → CloudWatch Logs |
| **Alertas** | Alertmanager + Grafana Alerts | CloudWatch Alarms + SNS |

**Instrumentación unificada:** OpenTelemetry Java Agent (auto-instrumentación sin cambios en el código de dominio) + Micrometer Prometheus para métricas de aplicación.

---

## Artefactos a Crear

### 1. Modificación a `.claude/skills/development-plan/SKILL.md`

La observabilidad se incorpora directamente en la skill existente `development-plan` como una **Etapa 0c** nueva, sin crear ninguna skill adicional.

**Cambios en `SKILL.md`:**

- **`# DOCUMENTOS A GENERAR`**: añadir la línea del nuevo documento a la estructura de `docs/development/`:
  ```
  ├── DEV-[proyecto]-0c-observability.md    # Etapa 0c: Stack de observabilidad (OTEL + Prometheus + CloudWatch)
  ```

- **Documento Maestro (`roadmap.md`)**: añadir la Etapa 0c en la tabla de etapas, posicionada entre la Etapa 0 (infraestructura) y la Etapa 1 (bases de datos), con dependencia `Etapa 0 completa` y esfuerzo estimado de 0.5 días.

- **Nueva sección `## Etapa 0c — DEV-[proyecto]-0c-observability.md`**: estructura obligatoria del documento que la skill genera. Secciones en orden exacto:
  1. Objetivo y stack de observabilidad (tabla dev vs staging/prod)
  2. Prerrequisitos (Etapa 0 completa, cluster K3d corriendo)
  3. Instalación del stack en K3d (`bash .claude/scripts/setup-observability.sh -P <proyecto>`) + tabla de endpoints
  4. Instrumentación de microservicios Spring Boot (dependencias Maven, `application.yml`, `logback-spring.xml`)
  5. Instrumentación de jobs Spark/Scala (si el diseño incluye reportería)
  6. Modificaciones a los Helm charts (annotations Prometheus, env vars OTEL, init container del agente)
  7. Dashboards y alertas (Grafana dev / CloudWatch Alarms + SNS staging/prod)
  8. Terraform CloudWatch (staging/prod): módulo `observability/`
  9. Integración con CI/CD: smoke test `/actuator/prometheus` en `runSmokeTests`
  10. Criterios de aceptación

- **Etapa 2 (`02-scaffold.md`)**: añadir nota explícita indicando que `maven_hexagonal_scaffold.py` ya genera las dependencias de observabilidad, la configuración Actuator/OTEL en `application.yml`, `logback-spring.xml` y las annotations/init container en el Helm chart — el desarrollador no necesita instrumentar manualmente.

- **Etapa 5 (`05-tests.md`)**: añadir en la sección de pruebas de integración la verificación E2E de observabilidad (traza generada, métrica scrapeada, log estructurado con `traceId`).

---

### 2. Script — `.claude/scripts/setup-observability.sh`

Instala el stack de observabilidad en el cluster K3d del proyecto. Se ejecuta después de la Etapa 0 (`init-dev-environment.sh`) y antes de la Etapa 2b (CI/CD).

**Parámetros:** `-P <nombre-proyecto>` (obligatorio, mismo patrón que el resto de scripts).

**Qué hace (pasos secuenciales):**

| Paso | Acción | Resultado esperado |
|---|---|---|
| 1 | Añade repositorios Helm (`prometheus-community`, `grafana`, `jaeger-all-in-one`, `fluent`) | Repos disponibles |
| 2 | Instala `kube-prometheus-stack` en namespace `monitoring` (K3d) | Prometheus `:9090`, Grafana `:3000` (port-forward) |
| 3 | Instala Jaeger all-in-one en namespace `tracing` | Jaeger UI `:16686` (port-forward) |
| 4 | Despliega OTEL Collector como Deployment en `monitoring` con ConfigMap | Endpoint OTLP `:4317` (gRPC) disponible en cluster |
| 5 | Despliega Fluent Bit DaemonSet apuntando a Loki | Logs de pods disponibles en Grafana |
| 6 | Persiste endpoints y variables en `terraform/backend/environments/dev/.observability-env` | Archivo leído por microservicios en dev |
| 7 | Verifica que todos los pods están `Running` y muestra tabla de endpoints | Checklist ✓ |

**Endpoints locales tras ejecución:**

```
Prometheus   → http://localhost:9090
Grafana      → http://localhost:3000  (admin/admin)
Jaeger UI    → http://localhost:16686
OTEL gRPC    → http://[proyecto]-otel-collector.monitoring:4317  (interno K3d)
CloudWatch   → solo staging/prod (no emulado en dev)
```

---

### 3. Modificaciones a `maven_hexagonal_scaffold.py`

El scaffold de microservicios Spring Boot incorpora las dependencias de observabilidad en el `pom.xml` generado y las configuraciones en `application.yml` y `logback-spring.xml`.

**Dependencias Maven a añadir al scaffold:**

```xml
<!-- Actuator + Prometheus -->
spring-boot-starter-actuator
micrometer-registry-prometheus

<!-- Trazas OTEL via Micrometer Bridge -->
micrometer-tracing-bridge-otel
opentelemetry-exporter-otlp

<!-- Logs estructurados JSON -->
logstash-logback-encoder:7.4
```

**`application.yml` generado — sección de observabilidad:**

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,readiness,liveness,prometheus,info,metrics
  metrics:
    tags:
      application: ${spring.application.name}
      environment: ${APP_ENV:dev}

spring:
  application:
    name: <nombre-servicio>

# OTEL — inyectado vía JAVA_TOOL_OPTIONS desde el secret de floci / K8s ConfigMap
# OTEL_SERVICE_NAME, OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_RESOURCE_ATTRIBUTES
```

**`logback-spring.xml` generado:**

```xml
<appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
  <encoder class="net.logstash.logback.encoder.LogstashEncoder">
    <includeMdcKeyName>traceId</includeMdcKeyName>
    <includeMdcKeyName>spanId</includeMdcKeyName>
    <includeMdcKeyName>service</includeMdcKeyName>
  </encoder>
</appender>
```

Los campos `traceId` y `spanId` los inyecta automáticamente el bridge Micrometer-OTEL en el MDC, correlacionando logs con trazas.

---

### 4. Modificaciones a los Helm charts generados

Cada chart generado por `maven_hexagonal_scaffold.py` recibe en `templates/deployment.yaml`:

**Annotations Prometheus (scrape automático):**

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/actuator/prometheus"
  prometheus.io/port: "{{ .Values.service.port }}"
```

**Variables de entorno OTEL:**

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "{{ .Chart.Name }}"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "{{ .Values.otel.collectorEndpoint }}"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment={{ .Values.env }},service.version={{ .Values.image.tag }}"
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/otel/opentelemetry-javaagent.jar"
```

**Init container para el OTEL Java Agent:**

```yaml
initContainers:
  - name: otel-agent
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
    command: ["cp", "/javaagent.jar", "/otel/opentelemetry-javaagent.jar"]
    volumeMounts:
      - name: otel-agent
        mountPath: /otel
volumes:
  - name: otel-agent
    emptyDir: {}
```

**`values-dev.yaml`:**
```yaml
otel:
  collectorEndpoint: "http://[proyecto]-otel-collector.monitoring:4317"
```

**`values-staging.yaml` / `values-prod.yaml`:**
```yaml
otel:
  collectorEndpoint: "http://otel-collector.monitoring:4317"  # → exporta a X-Ray
```

---

### 5. Módulo Terraform — `terraform/backend/modules/observability/`

Para staging/prod (EKS + AWS real). Dev usa K3d, no necesita este módulo.

**Recursos a generar:**

```
terraform/backend/modules/observability/
├── variables.tf         # org, env, services[], retention_days, alarm_thresholds
├── cloudwatch_logs.tf   # aws_cloudwatch_log_group por servicio
├── cloudwatch_metrics.tf # Container Insights, custom metric alarms
├── xray.tf              # aws_xray_group, sampling rules
├── alarms.tf            # CPU, memory, error_rate, p99_latency por servicio
├── sns.tf               # aws_sns_topic + aws_sns_topic_subscription (email/Slack)
└── outputs.tf           # log_group_names, alarm_arns
```

**Integración con ambiente:** `terraform/backend/environments/staging/main.tf` y `prod/main.tf` llaman al módulo con `module "observability" { source = "../../modules/observability" ... }`.

**OTEL Collector en EKS — ConfigMap staging/prod:**

El Collector recibe trazas OTLP de los microservicios y las exporta a X-Ray:
```yaml
exporters:
  awsxray:
    region: us-east-1
  awsemf:                       # métricas → CloudWatch EMF
    region: us-east-1
    log_group_name: /[proyecto]/metrics
```

---

### 6. Integración con `base-infrastructure-builder.sh`

Añadir instrucción de referencia en el script (sin lógica automática en esta fase) para que el desarrollador sepa cuándo ejecutar `setup-observability.sh`:

```
Etapa 0  → base-infrastructure-builder.sh   (floci + K3d)
Etapa 0b → init-dev-environment.sh          (Terraform apply)
Etapa 0c → setup-observability.sh           (Prometheus + Grafana + Jaeger + OTEL)  ← NUEVO
```

---

### 7. Integración con el pipeline CI/CD (Jenkins shared library)

Añadir al step `runQualityGates` de la shared library la validación de un SLO mínimo antes de promover a staging:

- `mvn test` produce reporte de cobertura → SonarQube ya lo valida.
- **Nuevo:** verificar que el endpoint `/actuator/prometheus` del servicio desplegado en K3d responde `200` (smoke test de observabilidad) como parte de `runSmokeTests`.

Esto se documenta en la skill como criterio de aceptación del pipeline, no como cambio de código de la shared library.

---

## Posición en el SDLC

La observabilidad se incorpora en tres momentos del flujo existente:

```
Etapa 0   — Infraestructura local
Etapa 0c  — [NUEVO] Stack de observabilidad K3d  (setup-observability.sh)
Etapa 2   — Scaffold  →  ya incluye dependencias OTEL + Micrometer + Logback JSON
Etapa 2b  — CI/CD     →  smoke test /actuator/prometheus
Etapa 3   — Microservicios  →  DEV-[proyecto]-observability.md referenciado en prerrequisitos
Etapa 5   — Tests     →  E2E de observabilidad (traza generada, métrica scrapeada, log emitido)
```

---

## Artefactos — Resumen

| Artefacto | Ubicación | Tipo | Estado |
|---|---|---|---|
| Modificación skill `development-plan` | `.claude/skills/development-plan/SKILL.md` | Edición | ✓ Aplicado |
| Script de instalación K3d | `.claude/scripts/setup-observability.sh` | Script bash | ✓ Creado |
| Módulo Terraform CloudWatch | `terraform/backend/modules/observability/` | Terraform | Generado por skill al invocar `/development-plan` |
| Dependencias en scaffold Maven | `.claude/templates/maven_hexagonal_scaffold.py` | Modificación | ✓ Aplicado |
| Modificaciones Helm chart | `.claude/templates/maven_hexagonal_scaffold.py` | Modificación | ✓ Aplicado |
| Plan por proyecto | `docs/development/DEV-[proyecto]-observability.md` | Generado por skill | Generado al invocar `/development-plan` |
| OTEL Collector ConfigMap K3d | Generado por `setup-observability.sh` (YAML inline) | YAML | ✓ Incluido en script |
| Fluent Bit DaemonSet K3d | Generado por `setup-observability.sh` (via Helm) | Helm | ✓ Incluido en script |

---

## Criterios de Aceptación del Plan

Una vez implementado todo lo anterior, cualquier proyecto generado con este SDLC cumple:

- [ ] `setup-observability.sh -P <proyecto>` finaliza con checklist ✓ en K3d.
- [ ] Prometheus scrapea `/actuator/prometheus` de todos los microservicios sin configuración manual.
- [ ] Una traza end-to-end aparece en Jaeger al hacer una request HTTP al primer microservicio.
- [ ] Los logs en Grafana/Loki muestran JSON con campos `traceId`, `spanId`, `service`, `level`.
- [ ] En staging/prod: CloudWatch Log Group `/[proyecto]/<servicio>` existe y recibe logs estructurados.
- [ ] En staging/prod: CloudWatch X-Ray muestra trazas del servicio.
- [ ] El pipeline Jenkins incluye smoke test de `/actuator/prometheus` en `runSmokeTests`.
- [ ] Añadir un nuevo microservicio vía `scaffold-all-services.sh` lo incorpora automáticamente al stack sin pasos manuales.
