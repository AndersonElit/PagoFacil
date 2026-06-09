# Etapa 2b — Configuración del Pipeline CI/CD

## 1. Objetivo

Configurar el pipeline CI/CD completo **antes** de iniciar la implementación de los servicios, de modo que cada commit sea validado automáticamente desde el primer día de desarrollo.

El modelo adoptado es **Jenkins CI → `bumpImageTag` → ArgoCD CD** con sincronización automática en `dev` y `staging`, y aprobación manual en `prod`.

### Diagrama de flujo

```
git push
    │
    ▼
Jenkins (stages)
  ├── build & test
  ├── quality gates (SonarQube)
  ├── security scan (Trivy)
  ├── build & push image → Gitea Registry / ECR
  └── bumpImageTag → helm/<service>/values-<env>.yaml
                          │
                          ▼
                   ArgoCD (GitOps)
                     ├── auto-sync → K3s VPS (dev)
                     ├── auto-sync → EKS (staging)
                     └── sync manual → EKS (prod)
```

**Fronteras CI/CD (GitOps puro):** Jenkins escribe únicamente en Git (actualiza el tag de imagen en los values de Helm). ArgoCD lee de Git y reconcilia el estado del cluster. Ninguna herramienta invoca directamente a la otra.

---

## 2. Prerrequisitos

### Infraestructura

| Entorno | Requisito | Descripción |
|---|---|---|
| **Dev** | Etapa 0 completa | K3s en VPS, Jenkins como systemd, ArgoCD en K3s, Gitea Package Registry, SonarQube operativos |
| **Dev** | Etapa 2 completa | `Jenkinsfile`, `Dockerfile` y Helm charts generados para todos los servicios |
| **Staging/Prod** | Módulos Terraform aplicados | `terraform/modules/jenkins` y `terraform/modules/argocd` aplicados sobre EKS |

### Herramientas locales requeridas

- `kubectl` configurado con kubeconfig: `terraform/backend/environments/dev/.kube/config-k3s`
- `docker` con acceso al registro `<VPS_IP>:3000`
- `bash` 4.x o superior
- `curl` y `jq` para verificaciones

---

## 3. Ejecución automatizada (recomendado)

El script `setup-cicd-pipeline.sh` orquesta todos los pasos (0 a 6) de forma autónoma en el entorno **dev**. Para staging/prod, los pasos deben ejecutarse manualmente o adaptarse al pipeline de IaC.

```bash
bash .claude/scripts/setup-cicd-pipeline.sh \
  -P pagofacil \
  -S identity-service,wallet-service,fraud-compliance-service,notification-service,integration-service,audit-service,reporting-projection-service,report-extraction-service,report-processing-service \
  --vps-ip <VPS_IP> \
  -F pagofacil-web
```

### Secciones internas del script

| Sección | Descripción |
|---|---|
| **0 — Shared Library** | Genera y publica `jenkins-shared-library` en Gitea |
| **1 — Imagen controller** | Construye y pushea `pagofacil-jenkins:latest` al registro Gitea |
| **2 — Bootstrap cluster K3s** | Aplica RBAC del agente Jenkins sobre K3s |
| **3 — .env JCasC + Jenkins systemd** | Inyecta variables y credenciales al controller vía JCasC |
| **4 — Jobs Jenkins** | Crea Multibranch Pipelines y webhooks en Gitea vía `/scriptText` |
| **5 — Bootstrap ArgoCD** | Aplica ApplicationSet con política de sync por entorno |
| **6 — Verificación** | Valida namespaces, jobs, aplicaciones ArgoCD y webhooks |

**Comportamiento en dev (completamente autónomo):**

- `SONAR_URL` y `SONAR_TOKEN` se autocompeltan desde el archivo `.sonar-env`.
- `GITOPS_GIT_USERNAME` y `GITOPS_GIT_TOKEN` se resuelven automáticamente usando `gitea-admin:gitea-admin`.
- Los jobs Jenkins se crean vía API Groovy en el endpoint `/scriptText` sin intervención manual.
- Los webhooks en Gitea se crean automáticamente para cada repositorio de servicio (eventos `push` y `pull_request`).
- La integración con Slack es **opcional**; si no se provee `SLACK_TOKEN`, el step `notify.groovy` omite las notificaciones sin fallar.

---

## 4. Paso 1: Generar la Shared Library

La Shared Library centraliza toda la lógica de pipeline reutilizable. Se genera una única vez y se versiona en Gitea.

### Comando

```bash
bash .claude/scripts/jenkins-shared-library-builder.sh \
  -P pagofacil \
  -o jenkins-shared-library
```

En entorno **dev**, el script crea automáticamente el repositorio `pagofacil/jenkins-shared-library` en Gitea y realiza el push inicial.

**URL del repositorio:** `http://<VPS_IP>:3000/pagofacil/jenkins-shared-library.git`

### Estructura de directorios generada

```
jenkins-shared-library/
├── vars/
│   ├── buildBackendService.groovy
│   ├── buildScalaBatchJob.groovy
│   ├── computeImageTag.groovy
│   ├── runIntegrationTests.groovy
│   ├── runQualityGates.groovy
│   ├── runSecurityScans.groovy
│   ├── buildAndPushImage.groovy
│   ├── scanImage.groovy
│   ├── bumpImageTag.groovy
│   ├── runSmokeTests.groovy
│   └── notify.groovy
├── src/
│   └── org/pagofacil/
│       └── PipelineDefaults.groovy
├── resources/
│   └── org/pagofacil/
│       ├── podBackend.yaml
│       ├── podFrontend.yaml
│       └── podScalaBatch.yaml
├── bootstrap/
│   └── jenkins-agent-rbac.yaml
└── docker/
    ├── Dockerfile
    ├── plugins.txt
    └── jenkins.yaml
```

### Steps disponibles en `vars/`

| Step | Descripción |
|---|---|
| `buildBackendService.groovy` | Compila y ejecuta tests unitarios para servicios Spring Boot / WebFlux |
| `buildScalaBatchJob.groovy` | Compila y empaqueta jobs Spark Scala con SBT |
| `computeImageTag.groovy` | Calcula el tag de imagen a partir del SHA corto del commit y la rama |
| `runIntegrationTests.groovy` | Levanta entorno efímero y ejecuta tests de integración |
| `runQualityGates.groovy` | Analiza con SonarQube; acepta parámetro `projectType: 'sbt'` para Scala |
| `runSecurityScans.groovy` | Escanea dependencias con OWASP Dependency-Check |
| `buildAndPushImage.groovy` | Construye imagen Docker y la publica en Gitea Registry (dev) o ECR (staging/prod) |
| `scanImage.groovy` | Escanea la imagen publicada con Trivy; bloquea el pipeline si hay CVEs críticos |
| `bumpImageTag.groovy` | Actualiza `helm/<service>/values-<env>.yaml` con el nuevo tag y hace commit/push al repo |
| `runSmokeTests.groovy` | Ejecuta smoke tests contra el servicio recién desplegado |
| `notify.groovy` | Envía notificaciones a Slack (opcional en dev; omite silenciosamente si no hay token) |

### Plugins requeridos (`docker/plugins.txt`)

```
git
workflow-aggregator
pipeline-stage-view
blueocean
multibranch-scan-webhook-trigger
docker-workflow
kubernetes
sonarqube
matrix-auth
credentials
credentials-binding
plain-credentials
ssh-credentials
configuration-as-code
job-dsl
scm-api
branch-api
github-branch-source
gitea
cloudbees-folder
timestamper
ws-cleanup
junit
jacoco
warnings-ng
dependency-check-jenkins-plugin
```

> **Nota:** El plugin `multibranch-scan-webhook-trigger` es requerido para que los webhooks de Gitea activen el escaneo de ramas automáticamente.

---

## 5. Paso 2: Construir y publicar la imagen del controller

El controller Jenkins se ejecuta como contenedor con todos los plugins pre-instalados, evitando gestión manual de plugins en tiempo de ejecución.

### Dev

```bash
# Construir la imagen
docker build \
  -t <VPS_IP>:3000/pagofacil/pagofacil-jenkins:latest \
  jenkins-shared-library/docker/

# Autenticarse en el registro Gitea
docker login <VPS_IP>:3000 \
  -u gitea-admin \
  -p gitea-admin

# Publicar la imagen
docker push <VPS_IP>:3000/pagofacil/pagofacil-jenkins:latest
```

### Staging / Prod

Reemplazar `<VPS_IP>:3000/pagofacil` por el URI del repositorio ECR correspondiente. La autenticación se realiza con `aws ecr get-login-password`.

---

## 6. Paso 3: Bootstrap del cluster

Aplica el RBAC necesario para que el agente Jenkins pueda desplegar recursos en el cluster.

### Dev (K3s en VPS)

```bash
kubectl \
  --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  apply -f terraform/backend/environments/dev/argocd-bootstrap/jenkins-agent-rbac-dev.yaml
```

### Verificación

```bash
# Verificar que el namespace fue creado
kubectl \
  --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  get namespace jenkins

# Verificar que el ServiceAccount existe
kubectl \
  --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  get serviceaccount jenkins-agent -n jenkins
```

Resultado esperado:

```
NAME      STATUS   AGE
jenkins   Active   <tiempo>

NAME            SECRETS   AGE
jenkins-agent   0         <tiempo>
```

---

## 7. Paso 4: Variables de entorno y credenciales al controller (JCasC)

La configuración del controller Jenkins se inyecta mediante **Jenkins Configuration as Code (JCasC)**, evitando configuración manual por UI.

### Variables de entorno

| Variable | Dev | Staging/Prod | Fuente |
|---|---|---|---|
| `GITEA_REGISTRY` | `<VPS_IP>:3000/pagofacil` | ECR URI | Terraform output |
| `K3S_API_SERVER` | `https://<VPS_IP>:6443` | EKS endpoint | Terraform / kubeconfig |
| `K3S_CLUSTER_NAME` | `k3s-pagofacil-dev` | EKS cluster name | Terraform |
| `AWS_REGION` | — | `us-east-1` | Variable de entorno |
| `REGISTRY_INSECURE` | `true` | `false` | Variable de entorno |
| `SMOKE_USE_INCLUSTER` | `true` | `false` | Variable de entorno |
| `JENKINS_URL` | `http://<VPS_IP>:8080` | HTTPS URL | Variable de entorno |
| `JENKINS_TUNNEL` | `<VPS_IP>:50000` | JNLP endpoint | Variable de entorno |
| `SHARED_LIBRARY_REPO` | `http://<VPS_IP>:3000/pagofacil/jenkins-shared-library.git` | SCM URL | Autocompletado en dev |
| `SONAR_URL` | `http://<VPS_IP>:9000` | HTTPS URL | `.sonar-env` (auto en dev) |
| `SLACK_TEAM` | *(vacío en dev)* | workspace Slack | Opcional en dev |
| `GITOPS_GIT_USERNAME` | `gitea-admin` | Usuario SCM | Autocompletado en dev |
| `GITOPS_GIT_TOKEN` | `gitea-admin` | Token SCM | Autocompletado en dev |

> En **dev**, las variables marcadas como "auto" o provenientes de `.sonar-env` son resueltas automáticamente por el script. No se requiere intervención manual.

### Credenciales JCasC

| ID de credencial | Tipo | Descripción | Dev |
|---|---|---|---|
| `sonar-token` | Secret text | Token de autenticación SonarQube | Leído desde `.sonar-env` |
| `slack-token` | Secret text | Token del bot de Slack | Opcional; omitido si no se provee |
| `k3s-kubeconfig` | Secret file | Kubeconfig para el cluster K3s | `terraform/backend/environments/dev/.kube/config-k3s` |
| `gitea-registry-credentials` | Username/Password | Credenciales para Gitea Package Registry | `gitea-admin:gitea-admin` |
| `gitops-git-credentials` | Username/Password | Credenciales para operaciones GitOps (`bumpImageTag`) | `gitea-admin:gitea-admin` |

---

## 8. Paso 5: Crear jobs en Jenkins y webhooks en Gitea

Todos los jobs son de tipo **Multibranch Pipeline**, configurados para detectar ramas automáticamente y usar el `Jenkinsfile` en la raíz de cada repositorio.

**Trigger:** Plugin `multibranch-scan-webhook-trigger` con `token=<nombre-del-repo>`.

### Jobs a crear

| Job Jenkins | Repositorio Gitea | Puerto del servicio |
|---|---|---|
| `identity-service` | `pagofacil/identity-service` | 8081 |
| `wallet-service` | `pagofacil/wallet-service` | 8082 |
| `fraud-compliance-service` | `pagofacil/fraud-compliance-service` | 8083 |
| `notification-service` | `pagofacil/notification-service` | 8084 |
| `integration-service` | `pagofacil/integration-service` | 8085 |
| `audit-service` | `pagofacil/audit-service` | 8086 |
| `reporting-projection-service` | `pagofacil/reporting-projection-service` | 8087 |
| `report-extraction-service` | `pagofacil/report-extraction-service` | CronJob Spark |
| `report-processing-service` | `pagofacil/report-processing-service` | CronJob Spark |
| `pagofacil-web` | `pagofacil/pagofacil-web` | Frontend Next.js |

### Dev (automático)

La **Sección 4** del script `setup-cicd-pipeline.sh`:

1. Aplica un script Groovy vía el endpoint Jenkins `/scriptText` que crea todos los Multibranch Pipelines con su configuración SCM y de triggers.
2. Crea un webhook en cada repositorio de Gitea (eventos `push` y `pull_request`) apuntando a:

```
http://<VPS_IP>:8080/multibranch-webhook-trigger/invoke?token=<nombre-del-repo>
```

> El repositorio `jenkins-shared-library` queda **excluido** de la creación de webhooks, ya que sus cambios se recogen en el siguiente escaneo de pipeline.

### Staging / Prod (manual)

Crear los Multibranch Pipelines desde la UI de Jenkins o mediante el job DSL del módulo Terraform. Configurar los webhooks en el proveedor SCM correspondiente (GitHub, GitLab, etc.).

---

## 9. Paso 6: Bootstrap de ArgoCD (ApplicationSet)

ArgoCD gestiona el estado declarativo de todos los servicios en el cluster. Se usa un **ApplicationSet** para generar automáticamente una `Application` por servicio y entorno.

### Comando dev

```bash
kubectl \
  --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  apply -f terraform/backend/environments/dev/argocd-bootstrap/
```

### URLs de repositorios Gitea (dev)

```
http://<VPS_IP>:3000/pagofacil/<nombre-del-servicio>.git
```

### Política de sincronización por entorno

| Entorno | Política sync | Prune | Self-Heal | Aprobación |
|---|---|---|---|---|
| `dev` | Automated | Sí | Sí | Ninguna |
| `staging` | Automated | Sí | Sí | Ninguna |
| `prod` | Manual | No | No | Requerida |

El campo `helm/<service>/values-<env>.yaml` que actualiza `bumpImageTag` es leído directamente por ArgoCD para reconciliar el estado del cluster.

### Verificación

```bash
kubectl \
  --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  get applications -n argocd
```

Resultado esperado: todas las `Application` en estado `Synced` / `Healthy`.

---

## 10. Verificación del pipeline completo

Para validar el pipeline end-to-end sin afectar el desarrollo activo, se realiza un commit trivial sobre el servicio `identity-service` (sin dependencias externas).

### Procedimiento

```bash
# En el repositorio identity-service
echo "# CI/CD bootstrap verification" >> README.md
git add README.md
git commit -m "chore: verify CI/CD pipeline bootstrap"
git push origin main
```

### Checklist de stages exitosos en Jenkins

Verificar en la UI de Jenkins (o BlueOcean) que los siguientes stages completan correctamente:

- [ ] `Checkout` — código descargado sin errores
- [ ] `Build & Unit Tests` — compilación exitosa y tests unitarios en verde
- [ ] `Quality Gate` — análisis SonarQube aprobado
- [ ] `Security Scan` — sin CVEs críticos detectados
- [ ] `Build & Push Image` — imagen publicada en `<VPS_IP>:3000/pagofacil/identity-service:<tag>`
- [ ] `Scan Image` — Trivy sin hallazgos críticos
- [ ] `Bump Image Tag` — commit de actualización de tag en el repositorio GitOps
- [ ] `Smoke Tests` — tests básicos de disponibilidad aprobados
- [ ] `Notify` — notificación enviada (o step omitido si Slack no está configurado)

### Verificación en ArgoCD

```bash
kubectl \
  --kubeconfig terraform/backend/environments/dev/.kube/config-k3s \
  get application identity-service -n argocd
```

- [ ] Estado `Sync Status`: `Synced`
- [ ] Estado `Health Status`: `Healthy`

---

## 11. Criterios de Aceptación

### Entorno Dev

Los ítems marcados con **✓** son verificados automáticamente por el script `setup-cicd-pipeline.sh`. Los marcados con **□** requieren acción manual posterior.

**Shared Library y controller:**

- ✓ Repositorio `pagofacil/jenkins-shared-library` creado y con push inicial en Gitea
- ✓ Imagen `pagofacil-jenkins:latest` publicada en `<VPS_IP>:3000/pagofacil/`
- ✓ Todos los steps en `vars/` presentes y sin errores de sintaxis Groovy

**Cluster y RBAC:**

- ✓ Namespace `jenkins` existente en K3s
- ✓ `ServiceAccount jenkins-agent` creado en namespace `jenkins`
- ✓ `ClusterRoleBinding` del agente aplicado correctamente

**Jenkins controller:**

- ✓ Variables de entorno inyectadas mediante JCasC
- ✓ Credenciales `sonar-token`, `k3s-kubeconfig`, `gitea-registry-credentials`, `gitops-git-credentials` creadas
- ✓ Shared Library registrada y accesible desde el controller
- ✓ 10 Multibranch Pipelines creados (9 servicios backend + 1 frontend)
- ✓ Webhooks Gitea creados para todos los repositorios de servicio

**ArgoCD:**

- ✓ `ApplicationSet` aplicado en namespace `argocd`
- ✓ `Application` generada para cada servicio en entorno `dev`

**Pipeline end-to-end (validación manual):**

- [ ] Commit trivial en `identity-service` activa el webhook y dispara el pipeline
- [ ] Todos los stages de Jenkins completan sin errores
- [ ] Imagen con nuevo tag publicada en el registro Gitea
- [ ] Commit de `bumpImageTag` visible en el repositorio GitOps
- [ ] ArgoCD muestra `identity-service` en estado `Synced` / `Healthy`

---

### Entorno Staging / Prod

En staging y prod todos los pasos son **manuales**. El script `setup-cicd-pipeline.sh` no aplica a estos entornos.

- [ ] Módulos Terraform `jenkins` y `argocd` aplicados sobre EKS correctamente
- [ ] Variables de entorno y credenciales configuradas manualmente en el controller Jenkins (producción)
- [ ] Repositorios ECR creados y accesibles desde el agente Jenkins
- [ ] Multibranch Pipelines creados y apuntando a los repositorios SCM de staging/prod
- [ ] Webhooks configurados en el proveedor SCM correspondiente
- [ ] `ApplicationSet` de ArgoCD aplicado con política `manual` para `prod`
- [ ] Pipeline end-to-end verificado con commit trivial en rama `staging`
- [ ] Sincronización manual de ArgoCD en `prod` ejecutada y verificada
- [ ] Acceso a Jenkins y ArgoCD restringido mediante HTTPS y autenticación corporativa
