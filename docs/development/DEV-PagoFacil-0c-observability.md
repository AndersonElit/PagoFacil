# Etapa 0c — Stack de Observabilidad

**Proyecto:** PagoFacil — Billetera Digital
**Etapa:** 0c — Observabilidad (previa a Etapa 1)
**Versión:** 1.0
**Fecha:** 2026-06-08

---

## 1. Objetivo y Stack de Observabilidad

Esta etapa instala y valida el stack completo de observabilidad en el clúster K3s del VPS **antes** de arrancar la Etapa 1 (Bases de Datos). El objetivo es garantizar que cada microservicio, desde su primer despliegue, emita métricas, trazas distribuidas y logs estructurados en formato que sea consumible tanto en dev como en staging/prod sin cambios de código.

### Stack por Ambiente

| Pilar | Dev (K3s + VPS) | Staging / Prod (EKS + AWS) |
|---|---|---|
| **Trazas distribuidas** | OTEL Collector → Jaeger | OTEL Collector → AWS X-Ray |
| **Métricas** | Prometheus + Grafana | Amazon Managed Prometheus (AMP) + CloudWatch |
| **Logs** | Fluent Bit (DaemonSet) → Loki | aws-for-fluent-bit → CloudWatch Logs |
| **Alertas** | Alertmanager | CloudWatch Alarms + SNS |
| **Instrumentación** | OTEL Java Agent (init container) | OTEL Java Agent (init container) |
| **Scraping métricas** | Prometheus annotations en pods | AMP scrape config vía ADOT |

---

## 2. Prerrequisitos

- Etapa 0 completada: infraestructura base aprovisionada, K3s en el VPS operativo y kubeconfig disponible.
- Verificar que el clúster esté accesible:

```bash
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3s get nodes
```

La salida esperada es un nodo en estado `Ready`. Si el nodo no aparece, completar primero la Etapa 0.

---

## 3. Instalación del Stack en K3s

### Comando

```bash
bash .claude/scripts/setup-observability.sh -P pagofacil
```

### Qué hace el script

1. Agrega los repositorios Helm necesarios (`prometheus-community`, `grafana`, `jaegertracing`, `open-telemetry`).
2. Instala `kube-prometheus-stack` (Prometheus Operator + Grafana + Alertmanager) en el namespace `monitoring`.
3. Instala Jaeger (all-in-one para dev) en el namespace `tracing`.
4. Despliega el OTEL Collector (`opentelemetry-collector`) en el namespace `monitoring`, configurado para recibir trazas OTLP gRPC y reenviarlas a Jaeger.
5. Despliega Fluent Bit como DaemonSet en `monitoring`, configurado para recolectar logs de todos los pods y enviarlos a Loki.
6. Instala Loki (modo single-binary para dev) en el namespace `monitoring`.
7. Persiste el estado del entorno en `terraform/backend/environments/dev/.observability-env` con las URLs internas y externas del stack.

### Endpoints del Stack

| Componente | Acceso externo (VPS) | Acceso interno (K3s) |
|---|---|---|
| Prometheus | `http://<VPS_IP>:9090` | `prometheus-operated.monitoring:9090` |
| Grafana | `http://<VPS_IP>:3001` (admin / admin) | `pagofacil-grafana.monitoring:80` |
| Jaeger UI | `http://<VPS_IP>:16686` | `jaeger.tracing:16686` |
| OTEL Collector (gRPC) | — | `pagofacil-otel-collector.monitoring:4317` |
| Loki | — | `loki.monitoring:3100` |

> El acceso externo se expone via NodePort o port-forward durante dev. Cambiar las credenciales de Grafana (admin/admin) inmediatamente tras la instalación.

---

## 4. Instrumentación de Microservicios Spring Boot (Automática vía Scaffold)

El script `maven_hexagonal_scaffold.py` genera toda la instrumentación necesaria sin intervención manual al crear o regenerar un microservicio. A continuación se describe qué se genera y para qué.

### Dependencias Maven (`pom.xml`)

| Dependencia | Propósito |
|---|---|
| `spring-boot-starter-actuator` | Endpoints `/actuator/*` (health, readiness, liveness, prometheus) |
| `micrometer-registry-prometheus` | Exportación de métricas en formato Prometheus |
| `micrometer-tracing-bridge-otel` | Bridge entre Micrometer Tracing y OpenTelemetry SDK |
| `opentelemetry-exporter-otlp` | Exportación de trazas al OTEL Collector vía OTLP gRPC |
| `net.logstash.logback:logstash-logback-encoder:7.4` | Serialización de logs en JSON con campos `traceId` y `spanId` |

### `application.yml` — Configuración Actuator

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,readiness,liveness,prometheus,info,metrics
  endpoint:
    health:
      probes:
        enabled: true
  metrics:
    export:
      prometheus:
        enabled: true
```

Las variables de entorno OTEL (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `OTEL_RESOURCE_ATTRIBUTES`) se inyectan desde el Helm chart del microservicio; no se hardcodean en `application.yml`.

### `logback-spring.xml` — Logging Estructurado

- **Perfil `dev`:** `ConsoleAppender` con patrón legible por humanos que incluye `traceId` y `spanId`.
- **Perfiles no-dev (staging, prod):** `ConsoleAppender` con `LogstashEncoder`, que produce JSON por línea con los campos `timestamp`, `level`, `logger`, `message`, `traceId`, `spanId` y los campos MDC del contexto de dominio.

Fluent Bit recoge el stdout de los pods y lo reenvía a Loki (dev) o CloudWatch Logs (staging/prod).

---

## 5. Instrumentación de Jobs Spark/Scala (Reportería)

Los CronJobs K8s que ejecutan los jobs Spark del `report-extraction-service` se instrumentan de la siguiente manera:

### Trazas — OTEL Java Agent

```yaml
env:
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/otel/opentelemetry-javaagent.jar"
  - name: OTEL_SERVICE_NAME
    value: "report-extraction-service"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://pagofacil-otel-collector.monitoring:4317"
```

El init container `otel-agent` copia el agente desde `ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest` al volumen compartido `/otel`.

### Métricas Spark

```properties
# spark.metrics.conf
*.sink.prometheus.class=org.apache.spark.metrics.sink.PrometheusServlet
*.sink.prometheus.path=/metrics/prometheus
```

Prometheus hace scrape del endpoint `/metrics/prometheus` del driver pod via las annotations estándar.

### Logs

`logback-spark.xml` usa `LogstashEncoder` para producir JSON estructurado con `traceId` y `spanId`. Fluent Bit los recolecta igual que los demás pods.

---

## 6. Modificaciones a los Helm Charts (Automáticas vía Scaffold)

El script `maven_hexagonal_scaffold.py` genera las siguientes modificaciones en los Helm charts de cada microservicio Spring Boot. No se deben editar manualmente.

### Annotations en el Pod Template

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/path: "/actuator/prometheus"
  prometheus.io/port: "{{ .Values.service.port }}"
```

### Init Container `otel-agent`

```yaml
initContainers:
  - name: otel-agent
    image: ghcr.io/open-telemetry/opentelemetry-operator/autoinstrumentation-java:latest
    command: ["cp", "-r", "/javaagent.jar", "/otel/opentelemetry-javaagent.jar"]
    volumeMounts:
      - name: otel-agent
        mountPath: /otel
volumes:
  - name: otel-agent
    emptyDir: {}
```

### Variables de Entorno OTEL

| Variable | Valor |
|---|---|
| `OTEL_SERVICE_NAME` | `{{ .Values.app.name }}` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | `{{ .Values.otel.collectorEndpoint }}` |
| `OTEL_RESOURCE_ATTRIBUTES` | `deployment.environment={{ .Values.environment }},service.version={{ .Values.image.tag }}` |
| `JAVA_TOOL_OPTIONS` | `-javaagent:/otel/opentelemetry-javaagent.jar` |

### `values-dev.yaml`

```yaml
otel:
  collectorEndpoint: http://pagofacil-otel-collector.monitoring:4317
```

---

## 7. Dashboards y Alertas

### Dev — Grafana

Importar los siguientes dashboards desde la UI de Grafana (`http://<VPS_IP>:3001`):

| Dashboard | ID Grafana | Descripción |
|---|---|---|
| JVM Micrometer | `4701` | Heap, GC, threads, CPU por instancia |
| Spring Boot Statistics | `12685` | HTTP rate, error rate, latencia por endpoint |

El datasource Loki debe configurarse con URL `http://loki.monitoring:3100` para correlacionar logs con trazas en el panel de Jaeger.

### Dev — Alertmanager

| Alerta | Condición | Duración |
|---|---|---|
| `HighErrorRate` | Tasa de errores HTTP 5xx > 5 % | 5 minutos |
| `HighP99Latency` | P99 de latencia > 2 s | 5 minutos |

### Staging / Prod — Terraform

El stack de observabilidad para staging y prod se gestiona mediante el módulo Terraform:

```
terraform/backend/modules/observability/
```

#### Estructura del Módulo

| Archivo | Contenido |
|---|---|
| `variables.tf` | Variables: `environment`, `project`, `service_names`, `alarm_sns_arn` |
| `cloudwatch_logs.tf` | Log groups por microservicio con retención configurable |
| `cloudwatch_metrics.tf` | Metric filters sobre los log groups para error rate y latencia |
| `xray.tf` | Grupos X-Ray y reglas de muestreo por servicio |
| `alarms.tf` | CloudWatch Alarms para error rate > 5 % y P99 > 2 s |
| `sns.tf` | Tópico SNS y suscripciones de email/PagerDuty para alertas |
| `outputs.tf` | ARNs del tópico SNS, log group names, X-Ray group ARNs |

#### Servicios Cubiertos por el Módulo

- `identity-service`
- `wallet-service`
- `fraud-compliance-service`
- `notification-service`
- `integration-service`
- `audit-service`
- `projection-service`

---

## 8. Terraform — Módulo `observability/` (Staging / Prod)

### `variables.tf`

```hcl
variable "environment"    { type = string }
variable "project"        { type = string  default = "pagofacil" }
variable "service_names"  { type = list(string) }
variable "alarm_sns_arn"  { type = string }
variable "log_retention_days" { type = number  default = 30 }
```

### `cloudwatch_logs.tf`

Crea un log group `/pagofacil/<environment>/<service_name>` por cada entrada de `var.service_names`. La retención se define con `var.log_retention_days`.

### `cloudwatch_metrics.tf`

Define metric filters sobre cada log group para extraer:
- `ErrorCount` — líneas JSON con `level = "ERROR"`.
- `P99Latency` — campo numérico `http.response_time_ms` percentil 99 (via EMF o métrica custom).

### `xray.tf`

Crea un grupo X-Ray por servicio con filter expression `annotation.service_name = "<service_name>"` y una regla de muestreo con rate configurable (default 5 %).

### `alarms.tf`

Crea dos alarmas CloudWatch por servicio:
- `<service>-error-rate-alarm`: métrica `ErrorCount`, threshold > 5 % de las solicitudes en 5 min.
- `<service>-p99-latency-alarm`: métrica `P99Latency`, threshold > 2000 ms en 5 min.

### `sns.tf`

Crea un tópico SNS `pagofacil-<environment>-alerts` y adjunta suscripciones de email (ops team) y opcionalmente PagerDuty via HTTPS.

### `outputs.tf`

Exporta: `sns_topic_arn`, `log_group_names` (map service → ARN), `xray_group_arns` (map service → ARN).

---

## 9. Integración con CI/CD

El pipeline Jenkins de cada microservicio incluye el step `runSmokeTests` tras el despliegue. Este step verifica:

1. `GET /actuator/health/readiness` — respuesta HTTP 200 con `{ "status": "UP" }`.
2. `GET /actuator/prometheus` — respuesta HTTP 200 con contenido no vacío (confirma que el endpoint de métricas está activo).

Si alguno de los dos endpoints falla, el pipeline marca el stage como fallido y ArgoCD no avanza la sincronización.

---

## 10. Criterios de Aceptación

- [ ] `bash .claude/scripts/setup-observability.sh -P pagofacil` finaliza sin errores.
- [ ] Todos los pods en el namespace `monitoring` están en estado `Running`: Prometheus Operator, Prometheus, Grafana, Alertmanager, OTEL Collector, Loki.
- [ ] Todos los pods en el namespace `tracing` están en estado `Running`: Jaeger.
- [ ] Fluent Bit DaemonSet tiene un pod `Running` en cada nodo del clúster.
- [ ] `http://<VPS_IP>:9090/targets` muestra al menos el target `kube-state-metrics` en estado `UP`.
- [ ] `http://<VPS_IP>:3001` carga la UI de Grafana y permite login con admin/admin.
- [ ] Los dashboards JVM Micrometer (ID 4701) y Spring Boot Statistics (ID 12685) están importados y muestran datos tras el primer despliegue de microservicio.
- [ ] `http://<VPS_IP>:16686` carga la UI de Jaeger.
- [ ] Tras desplegar cualquier microservicio generado por scaffold, Jaeger muestra el nombre del servicio en el selector de servicios.
- [ ] Los logs de los pods de microservicios son JSON válido con campos `traceId` y `spanId` no vacíos en perfiles no-dev.
- [ ] `GET /actuator/prometheus` de cualquier microservicio responde HTTP 200.
- [ ] El módulo `terraform/backend/modules/observability/` existe y pasa `terraform validate` en el pipeline de staging/prod.
- [ ] El archivo `terraform/backend/environments/dev/.observability-env` fue creado por el script con las URLs internas.
