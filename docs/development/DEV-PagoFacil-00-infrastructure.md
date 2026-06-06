# Etapa 0 — Infraestructura Local

**Proyecto:** PagoFacil | **Ambiente:** dev (floci + K3d)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo

Provisionar la infraestructura local completa del entorno de desarrollo: contenedores de soporte en `floci-net` (floci/LocalStack, PostgreSQL, Kafka, Gitea, SonarQube, Narayana LRA, WireMock), el árbol Terraform multi-ambiente y el cluster Kubernetes K3d (`pagofacil-dev`) con ArgoCD instalado. Esta etapa es prerequisito de todas las demás.

---

## 2. Prerrequisitos

| Software | Versión mínima | Instalación |
|---|---|---|
| Docker Engine / Docker Desktop | 24.x | https://docs.docker.com/engine/install/ |
| k3d | 5.6.x | `curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh \| bash` |
| kubectl | 1.29.x | Via gestión de paquetes del SO |
| Terraform | 1.6.0 | Via tfenv o gestión de paquetes |
| Python | 3.11+ | Via gestión de paquetes |
| jq | 1.6+ | Via gestión de paquetes |
| aws CLI | 2.x | `pip install awscli` |
| git | 2.40+ | Via gestión de paquetes |
| floci CLI | Latest | Según documentación de floci |

**Requisito del kernel (Linux):** SonarQube requiere `vm.max_map_count >= 262144`. El script lo eleva automáticamente si tiene acceso `sudo`. Si no, aplica `SONAR_ES_BOOTSTRAP_CHECKS_DISABLE=true`.

---

## 3. Paso 1: Ejecutar el script de infraestructura base

```bash
bash .claude/scripts/base-infrastructure-builder.sh -P pagofacil
```

**Qué genera:**

```
terraform/
├── backend/
│   ├── modules/          # Módulos reutilizables (ecr, rds, eks, cognito, msk, secrets_manager, argocd, jenkins)
│   └── environments/
│       ├── dev/
│       │   ├── main.tf   # Providers: aws (floci), kubernetes/helm (K3d)
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   ├── .sonar-env       # SONAR_URL + SONAR_TOKEN (generado automáticamente)
│       │   └── .kube/
│       │       ├── config-k3d          # kubeconfig externo (localhost)
│       │       └── config-k3d-internal # kubeconfig interno (para Jenkins en floci-net)
│       ├── staging/
│       └── prod/
└── frontend/
    └── environments/
        ├── dev/
        ├── staging/
        └── prod/
```

**Contenedores levantados en dev (en `floci-net`):**

| Contenedor | Imagen | Puerto(s) |
|---|---|---|
| `floci` | `localstack/localstack` | `4566` |
| `pagofacil-postgres-dev` | `postgres:16.3-alpine` | `5432` |
| `pagofacil-kafka-dev` | `apache/kafka:3.7.0` | `9092`, `9093` (KRaft) |
| `gitea` | `gitea/gitea` | `3000`, `2222` (SSH) |
| `pagofacil-sonarqube` | `sonarqube:lts-community` | `9000` |
| `narayana-lra` | `quay.io/jbosstm/lra-coordinator` | `8180` |
| `wiremock` | `wiremock/wiremock` | `8888` |
| **K3d cluster** `pagofacil-dev` | k3d (K3s en Docker) | API: `6443`, registry: `5100` |

El script:
1. Levanta SonarQube **antes** de K3d para que CoreDNS lo resuelva en `floci-net`.
2. Aprovisiona el token CI de SonarQube y lo persiste en `terraform/backend/environments/dev/.sonar-env` con `SONAR_URL` y `SONAR_TOKEN`.
3. Crea el usuario admin `gitea-admin` y la organización `pagofacil` en Gitea.
4. Crea el cluster K3d `pagofacil-dev` con el registry `k3d-pagofacil-registry:5100` sobre `floci-net`.
5. Escribe los kubeconfig de K3d en `terraform/backend/environments/dev/.kube/`.

---

## 4. Paso 2: Inicializar el ambiente dev (floci + K3d)

```bash
bash .claude/scripts/init-dev-environment.sh -P pagofacil
```

**Qué hace:**
1. `terraform init` y `terraform apply -auto-approve` desde `terraform/backend/environments/dev/`.
2. Verifica que los contenedores de soporte estén en estado `running`: `floci`, `pagofacil-postgres-dev`, `pagofacil-kafka-dev`, `gitea`, `pagofacil-sonarqube`, `narayana-lra`, `wiremock`.
3. Verifica recursos floci (S3 buckets, Cognito User Pool, ECR).
4. Verifica que el cluster K3d `pagofacil-dev` responde y que ArgoCD está instalado en namespace `argocd`.
5. Verifica conectividad entre contenedores en `floci-net`.
6. Imprime los outputs de Terraform (endpoints, IDs de recursos).
7. Imprime el checklist de verificación.

> **Nota:** En dev, los providers `kubernetes` y `helm` apuntan al kubeconfig K3d. El módulo `argocd` instala ArgoCD en el cluster K3d sin `-target` (K3d ya existe cuando se aplica Terraform).

### Tabla de endpoints locales (dev)

| Servicio | Endpoint externo (localhost) | Endpoint interno (floci-net) | Protocolo |
|---|---|---|---|
| floci (AWS mock) | `http://localhost:4566` | `http://floci:4566` | HTTP |
| PostgreSQL | `localhost:5432` | `pagofacil-postgres-dev:5432` | TCP |
| Kafka | `localhost:9092` | `pagofacil-kafka-dev:9092` | TCP |
| Gitea | `http://localhost:3000` | `http://gitea:3000` | HTTP |
| SonarQube | `http://localhost:9000` | `http://pagofacil-sonarqube:9000` | HTTP |
| Narayana LRA | `http://localhost:8180` | `http://narayana-lra:8180` | HTTP |
| WireMock | `http://localhost:8888` | `http://wiremock:8888` | HTTP |
| K3d API Server | `https://localhost:6443` | `https://k3d-pagofacil-dev-serverlb:6443` | HTTPS |
| K3d Registry | `http://localhost:5100` | `http://k3d-pagofacil-registry:5100` | HTTP |
| ArgoCD UI | `https://localhost:8443` (port-forward) | `argocd-server.argocd.svc` | HTTPS |

**Port-forward para la UI de ArgoCD:**

```bash
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  port-forward -n argocd svc/argocd-server 8443:443 &
```

---

## 5. Paso 3: Variables de entorno base

Crear el archivo `.env.dev` en la raíz del repositorio (no commitear, incluido en `.gitignore`):

| Variable | Valor | Descripción |
|---|---|---|
| `AWS_DEFAULT_REGION` | `us-east-1` | Región AWS (emulada por floci) |
| `AWS_ACCESS_KEY_ID` | `test` | Credencial mock de floci |
| `AWS_SECRET_ACCESS_KEY` | `test` | Credencial mock de floci |
| `AWS_ENDPOINT_URL` | `http://localhost:4566` | Endpoint de floci |
| `POSTGRES_HOST` | `localhost` | Host PostgreSQL dev |
| `POSTGRES_PORT` | `5432` | Puerto PostgreSQL dev |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092` | Broker Kafka dev |
| `NARAYANA_LRA_COORDINATOR_URL` | `http://localhost:8180/lra-coordinator` | Coordinador LRA |
| `WIREMOCK_BASE_URL` | `http://localhost:8888` | Simulador sistemas externos |
| `SONAR_URL` | `http://localhost:9000` | URL SonarQube |
| `KUBECONFIG` | `terraform/backend/environments/dev/.kube/config-k3d` | Kubeconfig K3d |

Obtener `SONAR_TOKEN` del archivo generado automáticamente:

```bash
source terraform/backend/environments/dev/.sonar-env
echo "SONAR_TOKEN=$SONAR_TOKEN"
```

---

## 6. Criterios de Aceptación

- [ ] `bash .claude/scripts/base-infrastructure-builder.sh -P pagofacil` finalizó con código de salida 0 y el árbol Terraform existe en `terraform/backend/environments/`.
- [ ] `bash .claude/scripts/init-dev-environment.sh -P pagofacil` finalizó con checklist ✓ (todos los contenedores `UP`).
- [ ] El contenedor `pagofacil-sonarqube` está `UP`: `curl -s http://localhost:9000/api/system/status | jq '.status'` retorna `"UP"`.
- [ ] El archivo `terraform/backend/environments/dev/.sonar-env` existe y contiene `SONAR_URL` y `SONAR_TOKEN` no vacíos.
- [ ] El cluster K3d responde: `kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d get nodes` muestra nodos `Ready`.
- [ ] ArgoCD está instalado: `kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d get pods -n argocd` muestra todos los pods `Running`.
- [ ] El registry K3d responde: `curl -s http://localhost:5100/v2/` retorna `{}`.
- [ ] Gitea está disponible con el admin: `curl -u gitea-admin:gitea-admin http://localhost:3000/api/v1/users/search?q=gitea-admin` retorna HTTP 200.
- [ ] La organización `pagofacil` existe en Gitea: `curl -u gitea-admin:gitea-admin http://localhost:3000/api/v1/orgs/pagofacil` retorna HTTP 200.
- [ ] Narayana LRA está disponible: `curl -s http://localhost:8180/lra-coordinator/` retorna HTTP 200.
- [ ] WireMock está disponible: `curl -s http://localhost:8888/__admin/` retorna HTTP 200.
- [ ] floci responde: `aws --endpoint-url=http://localhost:4566 sts get-caller-identity` retorna HTTP 200.
