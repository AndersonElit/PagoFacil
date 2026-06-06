# Etapa 0c — Stack de Observabilidad

**Proyecto:** PagoFacil | **Ambiente:** dev (floci + K3d)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo y Stack de Observabilidad

Instalar el stack de observabilidad en el cluster K3d `pagofacil-dev` y documentar la instrumentación que el scaffold incorpora automáticamente en cada microservicio. Esta etapa se ejecuta después de la Etapa 0 (`init-dev-environment.sh`) y antes de la Etapa 1 (bases de datos).

**Principio:** instrumentación unificada mediante OpenTelemetry Java Agent (sin cambios en el código de dominio) + Micrometer para métricas de aplicación. Los microservicios generados en la Etapa 2 ya llevan todas las dependencias y configuraciones de observabilidad — el desarrollador no instrumenta nada manualmente.

### Stack por ambiente

| Pilar | Dev (K3d `pagofacil-dev`) | Staging / Prod (EKS + AWS) |
|---|---|---|
| **Trazas** | OTEL Collector → Jaeger all-in-one | OTEL Collector → AWS X-Ray |
| **Métricas** | Prometheus (`kube-prometheus-stack`) + Grafana | Amazon Managed Prometheus (AMP) + CloudWatch Metrics |
| **Logs** | Fluent Bit DaemonSet → Loki + Grafana | `aws-for-fluent-bit` DaemonSet → CloudWatch Logs |
| **Alertas** | Alertmanager + Grafana Alerts | CloudWatch Alarms + SNS |

---

## 2. Prerrequisitos

- Etapa 0 completa: `bash .claude/scripts/base-infrastructure-builder.sh -P pagofacil` y `bash .claude/scripts/init-dev-environment.sh -P pagofacil` ejecutados con éxito.
- Cluster K3d `pagofacil-dev` corriendo: `k3d cluster list` muestra `pagofacil-dev` en estado `running`.
- `kubectl` apuntando al kubeconfig K3d: `export KUBECONFIG=terraform/backend/environments/dev/.kube/config-k3d`.
- `helm` instalado (≥ 3.14).

---

## 3. Instalación del Stack en K3d

```bash
bash .claude/scripts/setup-observability.sh -P pagofacil
```

El script ejecuta los siguientes pasos en orden:

| Paso | Acción | Verificación |
|---|---|---|
| 1 | Añade repos Helm: `prometheus-community`, `grafana`, `jaegertracing`, `fluent` | `helm repo list` |
| 2 | Instala `kube-prometheus-stack` en namespace `monitoring` | `kubectl get pods -n monitoring` |
| 3 | Instala Jaeger all-in-one en namespace `tracing` | `kubectl get pods -n tracing` |
| 4 | Despliega `pagofacil-otel-collector` (Deployment + Service + ConfigMap) en `monitoring` | `kubectl get deploy pagofacil-otel-collector -n monitoring` |
| 5 | Instala Loki + Fluent Bit DaemonSet en `monitoring` | `kubectl get ds fluent-bit -n monitoring` |
| 6 | Persiste endpoints en `terraform/backend/environments/dev/.observability-env` | `cat terraform/backend/environments/dev/.observability-env` |
| 7 | Verifica todos los pods en `Running` y muestra el checklist final | Checklist ✓ impreso en consola |

### Endpoints locales (port-forward)

| Componente | Comando port-forward | URL local |
|---|---|---|
| Prometheus | `kubectl port-forward svc/prometheus-operated 9090:9090 -n monitoring` | `http://localhost:9090` |
| Grafana | `kubectl port-forward svc/pagofacil-grafana 3000:80 -n monitoring` | `http://localhost:3000` (admin/admin) |
| Jaeger UI | `kubectl port-forward svc/jaeger 16686:16686 -n tracing` | `http://localhost:16686` |

> El kubeconfig para todos los comandos `kubectl` anteriores es `terraform/backend/environments/dev/.kube/config-k3d`. Anteponer `--kubeconfig terraform/backend/environments/dev/.kube/config-k3d` o exportar `KUBECONFIG` antes de ejecutar.

### Endpoints internos al cluster K3d (usados por los microservicios)

| Componente | Endpoint interno |
|---|---|
| OTEL Collector gRPC | `pagofacil-otel-collector.monitoring:4317` |
| OTEL Collector HTTP | `pagofacil-otel-collector.monitoring:4318` |
| Prometheus | `prometheus-operated.monitoring:9090` |
| Loki | `loki.monitoring:3100` |
| Jaeger Collector | `jaeger.tracing:4317` |

---

## 4. Instrumentación de Microservicios Spring Boot (automática vía scaffold)

> Esta sección es **referencia** de lo que `maven_hexagonal_scaffold.py` genera automáticamente. El desarrollador no realiza ninguna de estas acciones manualmente.

### Dependencias Maven — `pom.xml` raíz

Cada microservicio Spring Boot generado (identity-service, wallet-service, fraud-service, notification-service, audit-service, projection-service, integration-service) recibe en su `pom.xml` raíz:

```xml
<!-- Actuator + endpoint /actuator/prometheus -->
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>

<!-- Bridge Micrometer → OTEL (inyecta traceId/spanId en MDC automáticamente) -->
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-tracing-bridge-otel</artifactId>
</dependency>
<dependency>
    <groupId>io.opentelemetry</groupId>
    <artifactId>opentelemetry-exporter-otlp</artifactId>
</dependency>

<!-- Logs estructurados JSON -->
<dependency>
    <groupId>net.logstash.logback</groupId>
    <artifactId>logstash-logback-encoder</artifactId>
    <version>7.4</version>
</dependency>
```

### Configuración `application.yml`

Cada microservicio recibe en su `application.yml` el bloque:

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
```

Las variables OTEL (`OTEL_SERVICE_NAME`, `OTEL_EXPORTER_OTLP_ENDPOINT`, `JAVA_TOOL_OPTIONS`) se inyectan como variables de entorno desde el Helm chart — no van en `application.yml`.

### `logback-spring.xml`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
    <!-- Fuera de dev: JSON estructurado. traceId/spanId los inyecta el bridge Micrometer-OTEL en el MDC. -->
    <springProfile name="!dev">
        <appender name="JSON" class="ch.qos.logback.core.ConsoleAppender">
            <encoder class="net.logstash.logback.encoder.LogstashEncoder">
                <includeMdcKeyName>traceId</includeMdcKeyName>
                <includeMdcKeyName>spanId</includeMdcKeyName>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="JSON"/>
        </root>
    </springProfile>
    <!-- Dev: salida legible en consola con traceId/spanId visibles. -->
    <springProfile name="dev">
        <appender name="CONSOLE" class="ch.qos.logback.core.ConsoleAppender">
            <encoder>
                <pattern>%d{HH:mm:ss} %-5level [%X{traceId},%X{spanId}] %logger{36} - %msg%n</pattern>
            </encoder>
        </appender>
        <root level="INFO">
            <appender-ref ref="CONSOLE"/>
        </root>
    </springProfile>
</configuration>
```

---

## 5. Instrumentación de Jobs Spark/Scala (reportería)

Los jobs `report-extraction-service` (MS1) y `report-processing-service` (MS2) son CronJobs K8s — no servicios REST. La observabilidad se aplica así:

- **OTEL Java Agent:** inyectado vía `JAVA_TOOL_OPTIONS=-javaagent:/otel/opentelemetry-javaagent.jar` en el CronJob. El init container copia el agente igual que en los servicios Spring Boot.
- **Logs:** `logback-spark.xml` con `LogstashEncoder` (misma configuración que el backend). Los logs del CronJob son recolectados por Fluent Bit desde stdout y enviados a Loki.
- **Métricas:** en dev, las métricas del driver Spark se exponen en formato Prometheus habilitando `spark.metrics.conf` con `PrometheusServlet`; Prometheus las scrapea mediante annotations del pod.

---

## 6. Modificaciones a los Helm Charts (automáticas vía scaffold)

> Generadas por `maven_hexagonal_scaffold.py`. Aplican a todos los microservicios Spring Boot: identity-service, wallet-service, fraud-service, notification-service, audit-service, projection-service.

### `templates/deployment.yaml` — pod annotations (scrape automático de Prometheus)

```yaml
template:
  metadata:
    annotations:
      prometheus.io/scrape: "true"
      prometheus.io/path: "/actuator/prometheus"
      prometheus.io/port: "{{ .Values.service.port }}"
```

El `kube-prometheus-stack` detecta estas annotations y configura el scrape sin `ServiceMonitor` manual.

### `templates/deployment.yaml` — init container + volumen OTEL

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

### `templates/deployment.yaml` — variables de entorno OTEL

```yaml
env:
  - name: OTEL_SERVICE_NAME
    value: "{{ .Chart.Name }}"
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "{{ .Values.otel.collectorEndpoint }}"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "deployment.environment={{ .Values.env | default \"dev\" }},service.version={{ .Values.image.tag }}"
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/otel/opentelemetry-javaagent.jar"
```

### Valores por ambiente

**`values-dev.yaml`** de cada microservicio:
```yaml
otel:
  collectorEndpoint: "http://pagofacil-otel-collector.monitoring:4317"
```

**`values-staging.yaml` / `values-prod.yaml`** de cada microservicio:
```yaml
otel:
  collectorEndpoint: "http://otel-collector.monitoring:4317"
```
En staging/prod el OTEL Collector exporta a X-Ray (exporter `awsxray`) y a CloudWatch EMF (exporter `awsemf`).

---

## 7. Dashboards y Alertas

### Dev — Grafana (`http://localhost:3000`)

Importar los siguientes dashboards desde Grafana.com (Dashboards → Import → ID):

| Dashboard | ID Grafana.com | Propósito |
|---|---|---|
| JVM Micrometer | `4701` | Heap, GC, threads, buffer pools por servicio |
| Spring Boot Statistics | `12685` | HTTP request rate, latency, error rate |
| Loki Logs | — | Explorar logs JSON; filtrar por `traceId` para correlacionar con Jaeger |

**Alertas en Alertmanager (dev):**

| Alerta | Condición | Canal |
|---|---|---|
| `HighErrorRate` | `rate(http_server_requests_seconds_count{status=~"5.."}[5m]) / rate(http_server_requests_seconds_count[5m]) > 0.05` | Log en Alertmanager |
| `HighP99Latency` | `histogram_quantile(0.99, rate(http_server_requests_seconds_bucket[5m])) > 2` | Log en Alertmanager |
| `ServiceDown` | `up == 0` | Log en Alertmanager |

### Staging/Prod — AWS CloudWatch

El módulo Terraform `terraform/backend/modules/observability/` provisiona:

```
terraform/backend/modules/observability/
├── variables.tf          # org, env, services[], retention_days, alarm_thresholds
├── cloudwatch_logs.tf    # aws_cloudwatch_log_group por servicio: /pagofacil/<env>/<servicio>
├── cloudwatch_metrics.tf # Container Insights + metric alarms (CPU, memoria, error_rate, p99)
├── xray.tf               # aws_xray_group + sampling rules por servicio
├── alarms.tf             # aws_cloudwatch_metric_alarm: HighErrorRate, HighP99, ServiceDown
├── sns.tf                # aws_sns_topic "pagofacil-<env>-alerts" + subscriptions
└── outputs.tf            # log_group_names, alarm_arns, xray_group_arn
```

**Referencia en `staging/main.tf` y `prod/main.tf`:**

```hcl
module "observability" {
  source   = "../../modules/observability"
  org      = "pagofacil"
  env      = "staging"   # o "prod"
  services = [
    "identity-service", "wallet-service", "fraud-service",
    "notification-service", "audit-service", "projection-service",
    "integration-service", "report-extraction-service", "report-processing-service"
  ]
  retention_days = 30
}
```

**OTEL Collector en EKS (staging/prod) — ConfigMap:**

```yaml
exporters:
  awsxray:
    region: us-east-1
  awsemf:
    region: us-east-1
    log_group_name: /pagofacil/metrics
service:
  pipelines:
    traces:
      exporters: [awsxray]
    metrics:
      exporters: [awsemf]
```

---

## 8. Integración con CI/CD

El step `runSmokeTests` de la Shared Library (`jenkins-shared-library`) verifica dos endpoints tras cada despliegue en K3d dev:

1. `/actuator/health/readiness` → HTTP 200 con `status: UP` (ya existía).
2. `/actuator/prometheus` → HTTP 200 (confirma que el endpoint de métricas está activo).

En dev con auto-sync ArgoCD, después del primer despliegue de cada servicio verificar:

```bash
# Confirmar que el servicio aparece en Jaeger
curl -s http://localhost:16686/api/services | jq '.data[]'
# Debe incluir: "identity-service", "wallet-service", etc.
```

---

## 9. Criterios de Aceptación

- [ ] `bash .claude/scripts/setup-observability.sh -P pagofacil` finalizó con checklist ✓ y todos los pods en `Running`.
- [ ] `kubectl get pods -n monitoring` muestra Prometheus, Grafana (`pagofacil-grafana`), OTEL Collector (`pagofacil-otel-collector`) y Fluent Bit en `Running`.
- [ ] `kubectl get pods -n tracing` muestra Jaeger en `Running`.
- [ ] Prometheus (`http://localhost:9090 → Status > Targets`) muestra todos los microservicios desplegados como `UP` en `/actuator/prometheus`.
- [ ] Jaeger (`http://localhost:16686`) muestra al menos un servicio en la lista tras una request HTTP.
- [ ] Los logs en Grafana/Loki muestran JSON con campos `traceId`, `spanId`, `level`, `service` para todos los microservicios.
- [ ] `terraform/backend/environments/dev/.observability-env` existe con los endpoints correctos.
- [ ] En staging/prod (cuando se aprovisione): `terraform/backend/modules/observability/` existe y está referenciado en `staging/main.tf` y `prod/main.tf`.
- [ ] Añadir un nuevo microservicio vía `scaffold-all-services.sh` lo incorpora automáticamente al stack de observabilidad sin pasos manuales adicionales.
