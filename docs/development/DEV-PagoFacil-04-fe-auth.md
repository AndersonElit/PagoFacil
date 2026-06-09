# Etapa 4a — Frontend: Feature auth

**Proyecto:** PagoFacil — Billetera Digital
**Feature:** auth — Registro, autenticación MFA, callback OAuth2
**Roles de usuario:** público (no requiere JWT)
**Bounded context:** BC-01 Identity
**Microservicio dependiente:** identity-service (`:8081` via API Gateway)

---

## 1. Contexto y Objetivo

El feature `auth` cubre todas las rutas públicas de autenticación: registro con inicio de flujo KYC, autenticación de dos factores (email+password → MFA), callback OAuth2 con Cognito y cierre de sesión. Tras la autenticación exitosa el usuario es redirigido a `/wallets/[walletId]`.

---

## 2. Prerrequisitos

- [ ] Etapa 4 scaffold frontend completada (`pagofacil-web` generado en Gitea).
- [ ] Etapa 3a (`identity-service`) funcional y accesible via API Gateway.
- [ ] `frontend/pagofacil-web/.env.local` configurado: `COGNITO_ISSUER_URI`, `COGNITO_CLIENT_ID`, `NEXTAUTH_URL=http://VPS_IP:3000`, `NEXTAUTH_SECRET`, `NEXT_PUBLIC_API_BASE_URL=http://VPS_IP:8080`.
- [ ] NextAuth.js configurado con provider `Credentials`.

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/auth/login` | public, CSR | `LoginPage` | Formulario email+password; primer factor |
| `/auth/register` | public, CSR | `RegisterPage` | Formulario de registro; inicia KYC |
| `/auth/mfa` | public, CSR | `MfaPage` | Verificación MFA (TOTP / SMS OTP / email OTP) |
| `/auth/callback` | public, SSR | `CallbackPage` | Procesamiento callback OAuth2 Cognito |
| `/auth/logout` | protected, CSR | `LogoutPage` | Revocación de sesión |

> **TDD obligatorio — cada prueba Vitest de la Sección 9 se escribe y se ve FALLAR (Red) antes de implementar el artefacto (schema, hook, componente). Seguido de Refactor.**

---

## 4. Componentes — test-first

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `LoginForm` | Client Component | Campos email + password; validación Zod; submit → `useLogin`; estados loading/error; muestra 423 con `AccountBlockedAlert` |
| `RegisterForm` | Client Component | Campos email, phone_number, full_name, password, document_type, document_id; validación Zod; submit → `useRegister`; 202 → mensaje "KYC en proceso" |
| `MfaForm` | Client Component | Campo código MFA (6 dígitos); submit → `useMfaVerify`; timer de expiración del challenge |
| `AuthLayout` | Server Component | Layout de páginas de auth (logo PagoFacil, footer legal) |
| `AccountBlockedAlert` | Client Component | Alerta roja con mensaje "Cuenta bloqueada. Contacte soporte." visible cuando status 423 |

---

## 5. Integración con API (TanStack Query) — test-first

| Hook | Endpoint | Tipo | Descripción |
|---|---|---|---|
| `useRegister` | `POST /auth/register` | `useMutation` | Registro; maneja 409 (email duplicado), 422 (datos inválidos); en 202 muestra mensaje de KYC iniciado |
| `useLogin` | `POST /auth/login` | `useMutation` | Primer factor; en 200 devuelve `MFAChallengeResponse` y guarda en `authStore`; 423 muestra `AccountBlockedAlert` |
| `useMfaVerify` | `POST /auth/mfa/verify` | `useMutation` | En 200 guarda `TokenResponse` en NextAuth.js session y redirige a `/wallets/[walletId]` |
| `useRefreshToken` | `POST /auth/refresh` | `useMutation` | Renovación silenciosa; llamado por NextAuth.js `refreshAccessToken` |
| `useLogout` | `POST /auth/logout` | `useMutation` | Revoca sesión; llama `signOut()` de NextAuth.js; redirige a `/auth/login` |

---

## 6. Estado Global (Zustand)

`authStore`:
- `mfaChallenge: MFAChallengeResponse | null` — persiste entre LoginPage y MfaPage.
- `setMfaChallenge(challenge: MFAChallengeResponse): void`
- `clearMfaChallenge(): void`

---

## 7. Esquemas de Validación (Zod) — test-first

```typescript
// registerSchema
z.object({
  email: z.string().email("Email inválido"),
  phone_number: z.string().regex(/^\+[1-9]\d{7,14}$/, "Formato E.164").optional(),
  full_name: z.string().min(3, "Mínimo 3 caracteres"),
  password: z.string()
    .min(8, "Mínimo 8 caracteres")
    .regex(/[A-Z]/, "Debe contener mayúscula")
    .regex(/[0-9]/, "Debe contener número")
    .regex(/[^A-Za-z0-9]/, "Debe contener carácter especial"),
  document_type: z.enum(["CC", "CE", "PASSPORT"]),
  document_id: z.string().min(1, "Requerido"),
})

// loginSchema
z.object({
  email: z.string().email("Email inválido"),
  password: z.string().min(1, "Requerido"),
})

// mfaSchema
z.object({
  code: z.string().regex(/^\d{6}$/, "Debe ser exactamente 6 dígitos"),
})
```

---

## 8. Autenticación y Autorización

- Todas las rutas del feature son **públicas** — no requieren JWT.
- `middleware.ts` redirige a `/auth/login` si no hay sesión NextAuth.js en rutas protegidas (`/wallets/*`, `/transactions/*`, etc.).
- NextAuth.js configurado con provider `Credentials`:
  - `authorize()` llama a `POST /auth/login` + `POST /auth/mfa/verify`.
  - `jwt()` callback almacena el `access_token`, `refresh_token` y `expires_at`.
  - `session()` callback expone solo los claims necesarios al cliente.
  - `refreshAccessToken()` llama a `POST /auth/refresh` automáticamente.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> **Regla:** prueba FALLA (Red) antes del artefacto (Green). Seguido de Refactor.

### Schemas Zod

| Archivo de test | Caso de prueba | Schema que precede |
|---|---|---|
| `registerSchema.test.ts` | `should reject email without @` | `registerSchema` |
| `registerSchema.test.ts` | `should reject password without special char` | `registerSchema` |
| `registerSchema.test.ts` | `should reject full_name with less than 3 chars` | `registerSchema` |
| `loginSchema.test.ts` | `should accept valid email and password` | `loginSchema` |
| `mfaSchema.test.ts` | `should reject code with non-numeric chars` | `mfaSchema` |
| `mfaSchema.test.ts` | `should reject code shorter than 6 digits` | `mfaSchema` |

### Hooks (con MSW)

| Archivo de test | Escenario | Hook que precede |
|---|---|---|
| `useRegister.test.ts` | `should return success when API returns 202` | `useRegister` |
| `useRegister.test.ts` | `should handle 409 duplicate email error` | `useRegister` |
| `useLogin.test.ts` | `should return MFAChallengeResponse on 200` | `useLogin` |
| `useLogin.test.ts` | `should handle 423 blocked account` | `useLogin` |
| `useMfaVerify.test.ts` | `should store tokens on 200 response` | `useMfaVerify` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado | Componente que precede |
|---|---|---|
| `LoginForm.test.tsx` | `should show error when email format is invalid` | `LoginForm` |
| `LoginForm.test.tsx` | `should disable submit button while loading` | `LoginForm` |
| `AccountBlockedAlert.test.tsx` | `should display blocked message when 423 received` | `AccountBlockedAlert` |
| `RegisterForm.test.tsx` | `should show KYC started message on 202` | `RegisterForm` |
| `RegisterForm.test.tsx` | `should show duplicate email error on 409` | `RegisterForm` |
| `MfaForm.test.tsx` | `should accept only numeric input in code field` | `MfaForm` |

### Slices Zustand

| Archivo de test | Caso de prueba | Slice que precede |
|---|---|---|
| `authStore.test.ts` | `should set mfaChallenge and retrieve it` | `authStore` |
| `authStore.test.ts` | `should clear mfaChallenge on clearMfaChallenge()` | `authStore` |

**Umbral de cobertura del feature:** ≥ 80%

---

## 10. Pruebas E2E (Playwright, ATDD)

Flujos descritos **antes** de integrar el feature:

| Test | Flujo | Precondiciones | Resultado esperado |
|---|---|---|---|
| `auth-register-success.spec.ts` | Navegar a `/auth/register` → completar formulario → submit | MSW retorna 202 | Mensaje "KYC en proceso" visible en pantalla |
| `auth-login-mfa.spec.ts` | `/auth/login` → credenciales válidas → MFA challenge → `/auth/mfa` → código correcto | MSW retorna MFAChallenge luego TokenResponse | Redirige a `/wallets/[walletId]` |
| `auth-blocked-account.spec.ts` | `/auth/login` → credenciales → API retorna 423 | MSW retorna 423 | `AccountBlockedAlert` visible; sin redirect |
| `auth-duplicate-email.spec.ts` | `/auth/register` → email ya registrado | MSW retorna 409 | Error "Email ya registrado" en campo email |

---

## 11. Criterios de Aceptación

### TDD

- [ ] Cada schema, hook y componente tuvo su prueba escrita y vista fallar (Red) antes de la implementación (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] Cobertura del feature ≥ 80%.
- [ ] Flujos E2E de la Sección 10 pasan en Playwright.

### Funcionales

- [ ] Registro retorna 202 con mensaje de KYC iniciado.
- [ ] Email duplicado retorna error visible 409 en el formulario.
- [ ] Flujo login → MFA → redirect a `/wallets/[walletId]` funcional.
- [ ] Cuenta bloqueada (423) muestra `AccountBlockedAlert` sin redirigir.
- [ ] NextAuth.js almacena y refresca el access token automáticamente.
- [ ] Rutas protegidas redirigen a `/auth/login` cuando no hay sesión.
- [ ] Feature desplegado como pod en K3s via Ingress Traefik (no Vercel).
