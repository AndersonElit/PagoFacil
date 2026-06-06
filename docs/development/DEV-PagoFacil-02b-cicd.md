# Etapa 2b — Configuración del Pipeline CI/CD

**Proyecto:** PagoFacil | **Ambiente:** dev (floci + K3d)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Objetivo

Configurar el pipeline CI/CD completo antes de iniciar el desarrollo de los microservicios, para que cada commit de las etapas 3 y 4 sea validado automáticamente por el pipeline: build, tests, quality gate, imagen Docker y actualización del estado GitOps en ArgoCD.

**Modelo:** Jenkins CI → `bumpImageTag` (actualiza `helm/<service>/values-dev.yaml`) → ArgoCD CD (lee el repo Gitea, sincroniza al cluster K3d).

```
git push → Gitea webhook → Jenkins
                               │
    ┌──────────────────────────┘
    │ stages: build → tests → quality gate → push imagen → bumpImageTag
    │
    └─→ helm/<service>/values-dev.yaml (git push a Gitea)
                              │
                       ArgoCD (auto-sync) → K3d dev
                              │
                   (staging/prod: sync manual via ArgoCD UI)
                              │
              EKS staging/prod (Jenkins → ECR → ArgoCD → EKS)
```

**En dev:** el controller Jenkins corre como contenedor en `floci-net`. Los agentes Jenkins corren como pods en K3d (namespace `jenkins`). ArgoCD sincroniza aplicaciones sobre el cluster K3d.

**Frontend:** despliega a Vercel vía Jenkins CLI. ArgoCD no gestiona el frontend.

---

## 2. Prerrequisitos

- Etapa 2 completa: Jenkinsfiles, Dockerfiles y Helm charts generados para todos los servicios.
- Cluster K3d `pagofacil-dev` levantado y ArgoCD instalado (Etapa 0).
- SonarQube disponible en `http://localhost:9000` con token en `.sonar-env` (Etapa 0).
- Repositorios de servicios creados en Gitea (Etapa 2, push automático del scaffold).

---

## 0. Ejecución automatizada (recomendado)

```bash
bash .claude/scripts/setup-cicd-pipeline.sh -P pagofacil
```

**En dev, el script es completamente autónomo.** Ejecuta 7 secciones en orden:

| Sección | Descripción |
|---|---|
| 0 | Generar y publicar la Shared Library en Gitea |
| 1 | Construir imagen Docker del controller Jenkins |
| 2 | Bootstrap del cluster (namespace + ServiceAccount en K3d) |
| 3 | Levantar el controller Jenkins (`.env.jenkins` + `docker run`) |
| 4 | Crear jobs multibranch en Jenkins + webhooks en Gitea |
| 5 | Bootstrap ArgoCD (`kubectl apply -f argocd-bootstrap/`) |
| 6 | Verificación del pipeline completo |

La Sección 3 autocompleta `SONAR_URL`/`SONAR_TOKEN` desde `.sonar-env` y usa `gitea-admin:gitea-admin` para `GITOPS_GIT_USERNAME`/`GITOPS_GIT_TOKEN`. Slack es opcional en dev (`notify` hace fallback a `echo`). Variables Vercel no aplican en dev.

Los pasos siguientes documentan lo que cada sección realiza.

---

## 3. Paso 1: Generar la Shared Library

```bash
bash .claude/scripts/jenkins-shared-library-builder.sh -P pagofacil -o jenkins-shared-library
```

El script crea el repositorio `pagofacil/jenkins-shared-library` en Gitea y hace push automático de `main` con `gitea-admin:gitea-admin`.

**Árbol generado:**

```
jenkins-shared-library/
├── vars/
│   ├── computeImageTag.groovy
│   ├── buildBackendService.groovy
│   ├── buildScalaBatchJob.groovy
│   ├── runIntegrationTests.groovy
│   ├── runQualityGates.groovy
│   ├── runSecurityScans.groovy
│   ├── buildAndPushImage.groovy
│   ├── scanImage.groovy
│   ├── bumpImageTag.groovy
│   ├── runSmokeTests.groovy
│   └── notify.groovy
├── src/org/pagofacil/PipelineDefaults.groovy
├── resources/org/pagofacil/
│   ├── podBackend.yaml
│   ├── podFrontend.yaml
│   └── podScalaBatch.yaml
├── bootstrap/
│   └── jenkins-agent-rbac.yaml
└── docker/
    ├── Dockerfile
    ├── plugins.txt
    └── jenkins.yaml    (JCasC)
```

**Steps de `vars/` y su uso:**

| Archivo | Stage del pipeline | Descripción |
|---|---|---|
| `computeImageTag.groovy` | Compute Image Tag | Deriva tag de imagen del git SHA corto + rama |
| `buildBackendService.groovy` | Build (Maven) | `mvn clean package -DskipTests` |
| `buildScalaBatchJob.groovy` | Build (sbt) | `sbt clean test` + `sbt "entryPoints/assembly"` |
| `runIntegrationTests.groovy` | Integration Tests | `mvn verify` con Testcontainers |
| `runQualityGates.groovy` | Quality Gate | SonarQube scan; acepta `projectType:'sbt'` |
| `runSecurityScans.groovy` | Security Scan | OWASP Dependency-Check; acepta `projectType:'sbt'` |
| `buildAndPushImage.groovy` | Build & Push Image | Kaniko contra registry K3d o ECR |
| `scanImage.groovy` | Scan Image | Trivy |
| `bumpImageTag.groovy` | Bump Image Tag | Actualiza `values-<env>.yaml`, push a Gitea |
| `runSmokeTests.groovy` | Smoke Tests | `GET /actuator/health/readiness` en K3d (Maven) |
| `notify.groovy` | Notify | Slack si `SLACK_TEAM` no vacío, sino `echo` en log |

**Plugins del controller (`docker/plugins.txt`) — clave:**

```
kubernetes:latest
workflow-aggregator:latest
git:latest
pipeline-stage-view:latest
sonarqube:latest
dependency-check-jenkins-plugin:latest
docker-workflow:latest
credentials:latest
configuration-as-code:latest
job-dsl:latest
multibranch-scan-webhook-trigger:latest
```

El plugin `multibranch-scan-webhook-trigger` habilita el endpoint `/multibranch-webhook-trigger/invoke?token=<repo>` que dispara el escaneo del multibranch al recibir el webhook de Gitea.

---

## 4. Paso 2: Construir la imagen del controller

**Dev (K3d — solo build, sin push):**

```bash
cd jenkins-shared-library
docker build -t pagofacil-jenkins:latest docker/
```

La imagen no se publica en ningún registry. La Sección 3 del script la levanta automáticamente:

```bash
docker run -d \
  --name jenkins-controller \
  --network floci-net \
  -p 8080:8080 -p 50000:50000 \
  -v jenkins_home:/var/jenkins_home \
  -v terraform/backend/environments/dev/.kube/config-k3d-internal:/var/jenkins_home/.kube/config \
  --env-file .env.jenkins \
  pagofacil-jenkins:latest
```

> Recrear el contenedor conserva el volumen `jenkins_home`. El script espera a que Jenkins responda en `http://localhost:8080`.

**Staging/prod (ECR):** `docker build` + `aws ecr get-login-password | docker login` + `docker push`; actualizar `var.jenkins_image` en el módulo Terraform `jenkins` y ejecutar `terraform apply`.

---

## 5. Paso 3: Bootstrap del cluster (namespace + ServiceAccount)

**Dev (K3d — sin IRSA):**

```bash
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  apply -f terraform/backend/environments/dev/argocd-bootstrap/jenkins-agent-rbac-dev.yaml
```

El archivo `jenkins-agent-rbac-dev.yaml` crea:
- Namespace `jenkins`
- ServiceAccount `jenkins-agent` en namespace `jenkins`
- Role + RoleBinding para que los agentes puedan desplegar en namespace `dev`

**Verificación:**

```bash
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  get namespace jenkins
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  get serviceaccount jenkins-agent -n jenkins
```

---

## 6. Paso 4: Variables de entorno y credenciales al controller (JCasC)

### Variables de entorno inyectadas al controller

| Variable | Valor en dev | Fuente |
|---|---|---|
| `ECR_REGISTRY` | `k3d-pagofacil-registry:5100` | Terraform output (registry K3d) |
| `EKS_API_SERVER` | `https://k3d-pagofacil-dev-serverlb:6443` | Terraform output (K3d API) |
| `EKS_CLUSTER_NAME` | `pagofacil-dev` | Configuración K3d |
| `AWS_REGION` | `us-east-1` | Variable base |
| `REGISTRY_INSECURE` | `true` | Dev: registry HTTP sin TLS |
| `SMOKE_USE_INCLUSTER` | `true` | Dev: smoke tests in-cluster sin `aws eks` |
| `JENKINS_URL` | `http://jenkins-controller:8080` | Hostname del controller en floci-net |
| `JENKINS_TUNNEL` | `jenkins-controller:50000` | Tunnel para agentes |
| `SHARED_LIBRARY_REPO` | `http://gitea:3000/pagofacil/jenkins-shared-library.git` | URL interna Gitea |
| `SONAR_URL` | `http://pagofacil-sonarqube:9000` | Leído de `.sonar-env` (automático) |
| `SONAR_TOKEN` | `<token generado>` | Leído de `.sonar-env` (automático) |
| `GITOPS_GIT_USERNAME` | `gitea-admin` | Auto-completado (dev) |
| `GITOPS_GIT_TOKEN` | `gitea-admin` | Auto-completado (dev) |
| `SLACK_TEAM` | *(vacío en dev)* | Opcional; `notify` hace fallback a `echo` |
| `SLACK_TOKEN` | *(vacío en dev)* | Opcional |
| `VERCEL_TOKEN` | *(no aplica en dev)* | Requerido en staging/prod |
| `VERCEL_ORG_ID` | *(no aplica en dev)* | Requerido en staging/prod |
| `VERCEL_PROJECT_ID` | *(no aplica en dev)* | Requerido en staging/prod |

**Credenciales JCasC:**

| ID de credencial | Tipo | Descripción | Dev |
|---|---|---|---|
| `sonar-token` | Secret text | Token de análisis SonarQube | Automático (`.sonar-env`) |
| `slack-token` | Secret text | Token Webhook Slack | Opcional |
| `eks-kubeconfig` | Secret file | Kubeconfig del cluster | config-k3d-internal |
| `gitops-git-credentials` | Username/Password | Push a repos GitOps | `gitea-admin` / `gitea-admin` |

---

## 7. Paso 5: Crear los jobs de pipeline en Jenkins y webhooks en Gitea

**En dev (automático):** la Sección 4 del script aplica el Groovy de jobs vía `/scriptText` (auth anónima con crumb) y crea los webhooks en Gitea.

### Jobs a crear (Multibranch Pipeline)

| Job Name | Repositorio Gitea | SERVICE_NAME por defecto |
|---|---|---|
| `identity-service` | `http://gitea:3000/pagofacil/identity-service.git` | `identity-service` |
| `wallet-service` | `http://gitea:3000/pagofacil/wallet-service.git` | `wallet-service` |
| `fraud-service` | `http://gitea:3000/pagofacil/fraud-service.git` | `fraud-service` |
| `notification-service` | `http://gitea:3000/pagofacil/notification-service.git` | `notification-service` |
| `audit-service` | `http://gitea:3000/pagofacil/audit-service.git` | `audit-service` |
| `projection-service` | `http://gitea:3000/pagofacil/projection-service.git` | `projection-service` |
| `integration-service` | `http://gitea:3000/pagofacil/integration-service.git` | `integration-service` |
| `report-extraction-service` | `http://gitea:3000/pagofacil/report-extraction-service.git` | `report-extraction-service` |
| `report-processing-service` | `http://gitea:3000/pagofacil/report-processing-service.git` | `report-processing-service` |
| `pagofacil-web` | `http://gitea:3000/pagofacil/pagofacil-web.git` | `pagofacil-web` |

**Configuración de cada job:**
- Branch Sources: Gitea SCM con credenciales `gitops-git-credentials`.
- Build Configuration: detecta `Jenkinsfile` en la raíz del repositorio.
- Scan Triggers: webhook `multibranch-scan-webhook-trigger` con `token=<repo>` + scan periódico cada hora.

**Webhooks en Gitea (automático en dev):** la Sección 4 crea un webhook por cada repositorio de la org `pagofacil` apuntando a `http://jenkins-controller:8080/multibranch-webhook-trigger/invoke?token=<repo>` para eventos `push` y `pull_request`. Excluye `jenkins-shared-library`. Idempotente.

---

## 8. Paso 6: Bootstrap de ArgoCD (ApplicationSet por servicio)

```bash
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  apply -f terraform/backend/environments/dev/argocd-bootstrap/
```

El directorio `argocd-bootstrap/` contiene:
- `appset.yaml`: `ApplicationSet` con un elemento de lista por microservicio.
- `jenkins-agent-rbac-dev.yaml`: ServiceAccount para agentes Jenkins.

**URL del repositorio en el ApplicationSet (dev):**  
`http://gitea:3000/pagofacil/<servicio>.git`

### Política de sync por ambiente

| Ambiente | Política de sync | Auto-prune | Self-heal |
|---|---|---|---|
| `dev` | Automatizado | Sí | Sí |
| `staging` | Automatizado | Sí | Sí |
| `prod` | **Manual** (sync en UI de ArgoCD) | No | No |

**Verificación:**

```bash
kubectl --kubeconfig terraform/backend/environments/dev/.kube/config-k3d \
  get applications -n argocd
```

---

## 9. Verificación del pipeline completo

Después de completar el bootstrap, verificar el pipeline con un commit trivial en `identity-service` (el servicio sin dependencias externas):

```bash
cd backend/identity-service
echo "# test pipeline" >> README.md
git add README.md && git commit -m "test: verificar pipeline CI/CD"
git push
```

**Checklist de stages esperados en Jenkins (en verde):**

- [ ] Compute Image Tag
- [ ] Build (Maven)
- [ ] Integration Tests
- [ ] Quality Gate (SonarQube)
- [ ] Security Scan (OWASP)
- [ ] Build & Push Image (K3d registry)
- [ ] Scan Image (Trivy)
- [ ] Bump Image Tag (push a Gitea)
- [ ] Smoke Tests (K3d)
- [ ] Notify (echo en log)

**ArgoCD:** `kubectl get applications -n argocd identity-service -o jsonpath='{.status.sync.status}'` retorna `Synced`.

---

## 10. Criterios de Aceptación

**Automáticos (completados por `setup-cicd-pipeline.sh` en dev — ✓):**

- [x] Repositorio `pagofacil/jenkins-shared-library` existe en Gitea con rama `main` (Sección 0).
- [x] Imagen `pagofacil-jenkins:latest` construida (Sección 1).
- [x] Namespace `jenkins` y ServiceAccount `jenkins-agent` existen en K3d (Sección 2).
- [x] Archivo `.env.jenkins` generado con `SONAR_URL`/`SONAR_TOKEN` autocompletos (Sección 3).
- [x] Controller Jenkins en estado `running` y respondiendo en `http://localhost:8080` (Sección 3).
- [x] Jobs multibranch creados en Jenkins para todos los servicios (Sección 4).
- [x] Webhooks de Gitea creados para todos los repositorios de la org `pagofacil` (Sección 4).
- [x] `ApplicationSet` de ArgoCD aplicado en K3d (Sección 5).

**Manuales (requieren acción del desarrollador — □):**

- [ ] Commit trivial en `identity-service` disparó el pipeline en Jenkins y completó todos los stages en verde.
- [ ] ArgoCD muestra `identity-service` en estado `Synced` tras el pipeline.
- [ ] El pod de `identity-service` está `Running` en K3d: `kubectl get pods -n dev`.
