# Etapa 0 — Infraestructura VPS

## 1. Objetivo

Provisionar y validar el ambiente de desarrollo completo sobre un VPS Ubuntu 26.04 LTS. Al finalizar esta etapa, el VPS tendrá K3s operativo, todos los servicios de infraestructura corriendo como unidades systemd (PostgreSQL 16, MongoDB 7/8, Kafka KRaft, floci, SonarQube, Jenkins, LRA Coordinator, WireMock, Gitea) y los namespaces K3s creados para los workloads de PagoFacil. Esta etapa es prerequisito bloqueante para todas las demás.

---

## 2. Prerrequisitos

| Requisito | Detalle |
|---|---|
| VPS Ubuntu 26.04 LTS | Creado y accesible vía SSH. IP asignada como `<VPS_IP>`. |
| Script `qemu-vps.sh` | Disponible en `.claude/scripts/qemu-vps.sh`. Gestiona el ciclo de vida del VPS (create, start, stop, destroy). |
| Script `vps-setup.sh` | Disponible en `.claude/scripts/vps-setup.sh`. Instala y configura todos los servicios del stack en el VPS. |
| Acceso SSH sin contraseña | Clave pública desplegada en el VPS (`~/.ssh/authorized_keys`). |
| `kubectl` local | Configurado apuntando al cluster K3s del VPS (`KUBECONFIG` apuntando al kubeconfig exportado del VPS). |

El script `vps-setup.sh all` instala en el VPS:

- K3s (nativo, single-node)
- Docker Engine (para builds locales en el VPS)
- PostgreSQL 16 (systemd)
- MongoDB 7/8 (systemd — versión elegida automáticamente según soporte AVX del CPU)
- Apache Kafka 3 KRaft (systemd, puertos 9092 interno + 29092 externo)
- floci (systemd, puerto 4566)
- SonarQube Community (systemd, puerto 9000)
- Jenkins LTS (systemd, puerto 8080)
- ArgoCD (desplegado en K3s, NodePort 30080)
- Gitea (systemd, puerto 3000)
- Narayana LRA Coordinator (systemd, puerto 50000)
- WireMock standalone (systemd, puerto 9999)

---

## 3. Paso 0: Provisionar el VPS

### 3.1 Crear el VPS

```bash
bash .claude/scripts/qemu-vps.sh create --vcpus 4 --ram 8192 --disksize 60G
```

Próximos pasos:
  1. Conectar a la consola:   virsh console sdlc-vps
  2. Instalar Ubuntu (ver PLAN-VPS-LOCAL-QEMU.md § Paso 3)
  3. Ver IP asignada:         ./qemu-vps.sh status
  4. Config post-install:     ./qemu-vps.sh setup --vm-ip <IP>

# Ver IP asignada
virsh start sdlc-vps
.claude/scripts/qemu-vps.sh status

# Configuración post-instalación OCI-compatible (SSH key-only, sudo NOPASSWD,
# hostname, UTC, NTP, UFW, cloud-init NoCloud, sysctl vm.max_map_count)
.claude/scripts/qemu-vps.sh setup --vm-ip <VPS_IP>

# listar vm
virsh list --all

# Eliminar vm
bash .claude/scripts/qemu-vps.sh delete --vm-ip <VPS_IP> --force

### 3.2 Instalar todos los servicios del stack

# copiar llave publica
ssh-copy-id -i ~/.ssh/id_ed25519.pub ubuntu@<VPS_IP>

Te pide la contraseña una última vez, y después podés conectar con:

ssh ubuntu@<VPS_IP>

# Inhabilitar autenticacion con contraseña (esto se hace dentro de la vm)
echo "ubuntu ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/ubuntu-nopasswd
sudo chmod 440 /etc/sudoers.d/ubuntu-nopasswd

```bash
bash .claude/scripts/vps-setup.sh all \
  --vm-ip <VPS_IP> \
  --project pagofacil
```

Este comando es idempotente. Realiza la instalación completa de todos los servicios listados en la sección de Prerrequisitos. Al finalizar imprime un resumen de los servicios activos con sus puertos.

### 3.3 Verificar conectividad SSH

```bash
# Todos los servicios son unidades systemd — deben responder "active"
ssh ubuntu@<VPS_IP> "systemctl is-active postgresql mongodb kafka sonarqube jenkins gitea lra-coordinator wiremock floci"
```

Todos deben responder `active`.

> **Nota floci**: floci es un binario nativo (compilado con GraalVM) que gestiona un contenedor Docker interno. Se integra a systemd con `Type=oneshot RemainAfterExit=yes`, por lo que `systemctl is-active floci` devuelve `active` después de que `floci start` completa. Para reiniciarlo manualmente: `sudo systemctl restart floci`. Para ver el container subyacente: `docker ps --filter name=floci`.

#### Troubleshooting rápido

**SonarQube inactive** — Requiere `vm.max_map_count ≥ 524288` para su Elasticsearch embebido:
```bash
ssh ubuntu@<VPS_IP> "sudo sysctl -w vm.max_map_count=524288 && sudo systemctl restart sonarqube"
# Esperar ~90 s y verificar
ssh ubuntu@<VPS_IP> "systemctl is-active sonarqube"
```

**MongoDB inactive** — El script instala MongoDB 7 (sin AVX) o 8 (con AVX) automáticamente. Si falla:
```bash
ssh ubuntu@<VPS_IP> "grep -c avx /proc/cpuinfo"   # 0 = sin AVX
ssh ubuntu@<VPS_IP> "journalctl -u mongod -n 20 --no-pager"
```

> **Nota AVX en KVM**: Si se necesita MongoDB 8 específicamente y el CPU virtual no tiene AVX, editar la VM con `virsh edit sdlc-vps` y agregar `<cpu mode='host-passthrough'/>`. Luego `virsh shutdown sdlc-vps && virsh start sdlc-vps` y reejecutar `services`.

---

## 4. Paso 1: Ejecutar el script de infraestructura base

### 4.1 Comando

```bash
bash .claude/scripts/base-infrastructure-builder.sh \
  -P pagofacil \
  --vps-ip <VPS_IP>
```

### 4.2 Qué genera este script

El script ejecuta Terraform con el backend local y genera los siguientes recursos:

**Namespaces K3s:**

| Namespace | Propósito |
|---|---|
| `pagofacil-services` | Microservicios backend (identity, wallet, fraud, notification, integration, audit, projection) |
| `pagofacil-batch` | CronJobs de reportes (MS1, MS2) |
| `pagofacil-infra` | Kafka, Zookeeper (si aplica), recursos de infraestructura K3s |
| `pagofacil-gitops` | ArgoCD applications y AppProjects |
| `pagofacil-monitoring` | Prometheus, Grafana, Loki (Etapa 0c) |

**ConfigMaps y Secrets base en K3s:**

- `pagofacil-db-config` (namespace `pagofacil-services`) — host, puerto y nombre de base de datos por servicio.
- `pagofacil-kafka-config` — bootstrap servers interno (`kafka:9092`) y externo (`<VPS_IP>:29092`).
- `pagofacil-floci-config` — endpoint floci, región y credenciales dummy.
- `pagofacil-lra-config` — URL del coordinador LRA.

**Estructura Terraform (`infrastructure/dev/`):**

```
infrastructure/
  dev/
    main.tf          # Provider K3s + recursos base
    variables.tf
    outputs.tf
    terraform.tfvars
  modules/
    k3s-namespace/
    k3s-configmap/
    k3s-secret/
```

> **Nota importante:** El `dev/main.tf` **no incluye** módulos ECR, RDS ni MSK. Todos los servicios de datos y mensajería son gestionados por systemd directamente en el VPS. El registry de imágenes es Gitea: `gitea_registry = "<VPS_IP>:3000/pagofacil"`.

### 4.3 Verificar recursos K3s generados

```bash
kubectl get namespaces | grep pagofacil
kubectl get configmaps -n pagofacil-services
kubectl get secrets -n pagofacil-services
```

---

## 5. Paso 2: Inicializar el ambiente dev

### 5.1 Comando

```bash
bash .claude/scripts/init-dev-environment.sh \
  -P pagofacil \
  --vps-ip <VPS_IP>
```

Este script realiza las siguientes acciones:

1. Exporta el kubeconfig de K3s al archivo local `~/.kube/config-pagofacil-dev` y lo registra en `KUBECONFIG`.
2. Crea los usuarios y bases de datos PostgreSQL para todos los servicios (`pagofacil_app` como usuario de aplicación).
3. Crea las bases de datos MongoDB (`pagofacil_audit_service`) con el usuario `pagofacil_app`.
4. Crea los buckets S3 en floci: `pagofacil-reports`, `pagofacil-exports`.
5. Crea los topics Kafka iniciales.
6. Verifica que SonarQube esté UP y genera el archivo `.sonar-env` con token y URL.
7. Verifica que ArgoCD esté UP en el namespace `argocd` y crea el `AppProject` `pagofacil`.
8. Imprime el resumen de endpoints con estado.

### 5.2 Tabla de endpoints VPS post-inicialización

| Servicio | URL / Endpoint | Credenciales iniciales |
|---|---|---|
| PostgreSQL 16 | `<VPS_IP>:5432` | `pagofacil_app / <generada>` |
| MongoDB 7 | `mongodb://pagofacil_app:<CLAVE>@<VPS_IP>:27017/` | `pagofacil_app / <generada>` |
| Kafka KRaft (externo) | `<VPS_IP>:29092` | Sin autenticación (dev) |
| Kafka KRaft (interno K3s) | `kafka.pagofacil-infra.svc:9092` | Sin autenticación (dev) |
| floci (AWS emulado) | `http://<VPS_IP>:4566` | `test / test` (dummy) |
| SonarQube | `http://<VPS_IP>:9000` | `admin / admin` (cambiar en primer login) |
| Jenkins | `http://<VPS_IP>:8080` | Ver `initialAdminPassword` en el VPS |
| ArgoCD | `http://<VPS_IP>:30080` | `admin / <generada por K3s>` |
| K3s API Server | `https://<VPS_IP>:6443` | kubeconfig en `~/.kube/config-pagofacil-dev` |
| Gitea Package Registry | `http://<VPS_IP>:3000/pagofacil` | `pagofacil / <configurada en setup>` |
| LRA Coordinator | `http://<VPS_IP>:50000/lra-coordinator` | Sin autenticación (dev) |
| WireMock | `http://<VPS_IP>:9999` | Sin autenticación (dev) |

### 5.3 Topics Kafka creados

| Topic | Particiones | Replication Factor | Consumidores esperados |
|---|---|---|---|
| `identity.events` | 3 | 1 | projection-service, audit-service |
| `wallet.events` | 3 | 1 | projection-service, audit-service, integration-service |
| `compliance.events` | 3 | 1 | projection-service, audit-service |
| `notification.commands` | 3 | 1 | notification-service |
| `integration.events` | 3 | 1 | audit-service, projection-service |
| `saga.wallet.compensate` | 3 | 1 | wallet-service |
| `saga.compliance.compensate` | 3 | 1 | fraud-compliance-service |
| `audit.events` | 3 | 1 | audit-service |
| `reporting.extraction.ready` | 3 | 1 | report-processing-service |
| `reporting.processed.ready` | 3 | 1 | capa-serverless-lambda |

### 5.4 Bases de datos PostgreSQL creadas

| Base de datos | Usuario propietario | Servicio |
|---|---|---|
| `pagofacil_identity_service` | `pagofacil_app` | identity-service |
| `pagofacil_wallet_service` | `pagofacil_app` | wallet-service |
| `pagofacil_fraud_compliance_service` | `pagofacil_app` | fraud-compliance-service |
| `pagofacil_notification_service` | `pagofacil_app` | notification-service |
| `pagofacil_integration_service` | `pagofacil_app` | integration-service |
| `pagofacil_readmodel` | `pagofacil_app` | projection-service, report-extraction-service |
| `pagofacil_reporting` | `pagofacil_app` | report-extraction-service |

### 5.5 Base de datos MongoDB creada

| Base de datos | Usuario | Servicio |
|---|---|---|
| `pagofacil_audit_service` | `pagofacil_app` | audit-service |

---

## 6. Paso 3: Variables de entorno base

### 6.1 Archivo `.env` (raíz del repositorio)

Este archivo NO se versiona (está en `.gitignore`). Se genera automáticamente por `init-dev-environment.sh` con los valores reales.

| Variable | Valor | Descripción |
|---|---|---|
| `VPS_IP` | `<VPS_IP>` | IP del VPS de desarrollo |
| `GITEA_REGISTRY` | `<VPS_IP>:3000/pagofacil` | Registry OCI de imágenes del proyecto |
| `KAFKA_BOOTSTRAP` | `<VPS_IP>:29092` | Bootstrap server Kafka (acceso externo) |
| `KAFKA_BOOTSTRAP_INTERNAL` | `kafka.pagofacil-infra.svc:9092` | Bootstrap server Kafka (acceso interno K3s) |
| `POSTGRES_HOST` | `<VPS_IP>` | Host del servidor PostgreSQL |
| `POSTGRES_PORT` | `5432` | Puerto PostgreSQL |
| `POSTGRES_APP_USER` | `pagofacil_app` | Usuario de aplicación PostgreSQL |
| `POSTGRES_APP_PASSWORD` | `<CLAVE>` | Contraseña del usuario `pagofacil_app` |
| `MONGODB_URI` | `mongodb://pagofacil_app:<CLAVE>@<VPS_IP>:27017/` | URI de conexión MongoDB |
| `AWS_ENDPOINT_URL` | `http://<VPS_IP>:4566` | Endpoint floci (emulador AWS) |
| `AWS_DEFAULT_REGION` | `us-east-1` | Región AWS dummy para floci |
| `AWS_ACCESS_KEY_ID` | `test` | Credencial dummy floci |
| `AWS_SECRET_ACCESS_KEY` | `test` | Credencial dummy floci |
| `S3_BUCKET_REPORTS` | `pagofacil-reports` | Bucket S3 para reportes generados |
| `S3_BUCKET_EXPORTS` | `pagofacil-exports` | Bucket S3 para exportaciones |
| `LRA_COORDINATOR_URL` | `http://<VPS_IP>:50000/lra-coordinator` | URL del coordinador Narayana LRA |
| `WIREMOCK_URL` | `http://<VPS_IP>:9999` | URL de WireMock para stubs de sistemas externos |
| `SONARQUBE_URL` | `http://<VPS_IP>:9000` | URL de SonarQube |
| `SONARQUBE_TOKEN` | `<TOKEN>` | Token de análisis SonarQube (en `.sonar-env`) |
| `K3S_API` | `https://<VPS_IP>:6443` | URL del API server K3s |
| `KUBECONFIG` | `~/.kube/config-pagofacil-dev` | Ruta al kubeconfig del cluster |

### 6.2 Archivo `frontend/.env.local`

Este archivo NO se versiona. Se genera a partir de `frontend/.env.local.example`.

| Variable | Valor | Descripción |
|---|---|---|
| `NEXT_PUBLIC_API_BASE_URL` | `http://<VPS_IP>` | URL base de la API (sin puerto, via ingress si aplica) |
| `NEXT_PUBLIC_IDENTITY_SERVICE_URL` | `http://<VPS_IP>:8081` | identity-service |
| `NEXT_PUBLIC_WALLET_SERVICE_URL` | `http://<VPS_IP>:8082` | wallet-service |
| `NEXT_PUBLIC_INTEGRATION_SERVICE_URL` | `http://<VPS_IP>:8085` | integration-service |
| `NEXT_PUBLIC_FRAUD_SERVICE_URL` | `http://<VPS_IP>:8083` | fraud-compliance-service |
| `NEXT_PUBLIC_AUDIT_SERVICE_URL` | `http://<VPS_IP>:8086` | audit-service |
| `NEXT_PUBLIC_PROJECTION_SERVICE_URL` | `http://<VPS_IP>:8087` | projection-service |
| `NEXTAUTH_SECRET` | `<SECRET>` | Secret para NextAuth.js |
| `NEXTAUTH_URL` | `http://localhost:3001` | URL de callback del frontend en dev local |

---

## 7. Criterios de Aceptación

Los siguientes criterios deben verificarse manualmente o mediante el script `init-dev-environment.sh --verify` antes de declarar la Etapa 0 como completada.

### VPS y servicios systemd

- [ ] El script `init-dev-environment.sh` finaliza sin errores (exit code 0).
- [ ] PostgreSQL 16 responde en `<VPS_IP>:5432` y acepta conexiones con `pagofacil_app`.
- [ ] MongoDB 7 responde en `<VPS_IP>:27017` y acepta conexiones con `pagofacil_app`.
- [ ] Kafka KRaft responde en `<VPS_IP>:29092` — `kafka-topics.sh --list` devuelve los topics esperados.
- [ ] floci activo como servicio systemd: `systemctl is-active floci` devuelve `active`.
- [ ] floci responde en `http://<VPS_IP>:4566` — `aws --endpoint-url http://<VPS_IP>:4566 s3 ls` lista los buckets `pagofacil-reports` y `pagofacil-exports`.
- [ ] LRA Coordinator responde en `http://<VPS_IP>:50000/lra-coordinator` con HTTP 200.
- [ ] WireMock responde en `http://<VPS_IP>:9999/__admin/` con HTTP 200.

### SonarQube

- [ ] SonarQube responde en `http://<VPS_IP>:9000` con estado `UP`.
- [ ] El archivo `.sonar-env` existe en la raíz del repositorio con las variables `SONARQUBE_URL` y `SONARQUBE_TOKEN` definidas.
- [ ] El token registrado en `.sonar-env` es válido: `curl -u $SONARQUBE_TOKEN: $SONARQUBE_URL/api/authentication/validate` devuelve `{"valid":true}`.

### K3s

- [ ] `kubectl get nodes` muestra el nodo con estado `Ready`.
- [ ] Los namespaces `pagofacil-services`, `pagofacil-batch`, `pagofacil-infra`, `pagofacil-gitops` y `pagofacil-monitoring` existen.
- [ ] `kubectl get configmaps -n pagofacil-services` lista `pagofacil-db-config` y `pagofacil-kafka-config`.

### ArgoCD

- [ ] El namespace `argocd` existe en K3s: `kubectl get ns argocd` responde `Active`.
- [ ] ArgoCD UI responde en `http://<VPS_IP>:30080`.
- [ ] El `AppProject` `pagofacil` existe: `kubectl get appproject pagofacil -n argocd` responde sin error.

### Jenkins y Gitea

- [ ] Jenkins UI responde en `http://<VPS_IP>:8080`.
- [ ] Gitea UI responde en `http://<VPS_IP>:3000` y la organización `pagofacil` existe.
- [ ] El registry de Gitea acepta `docker pull <VPS_IP>:3000/pagofacil/hello-world` (imagen de prueba).

### Terraform

- [ ] `terraform show` en `infrastructure/dev/` no reporta recursos en estado `tainted` o `errored`.
- [ ] El archivo `infrastructure/dev/terraform.tfstate` existe y no está vacío.
