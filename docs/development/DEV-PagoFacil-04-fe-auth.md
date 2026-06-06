# Etapa 4 — Frontend: Feature auth

**Proyecto:** PagoFacil | **Frontend:** pagofacil-web (Next.js 15.3)  
**Documento relacionado:** [DEV-PagoFacil-roadmap.md](DEV-PagoFacil-roadmap.md)

---

## 1. Contexto y Objetivo

Implementar el flujo completo de autenticación: registro de nuevos usuarios, inicio de sesión con MFA, verificación del segundo factor, recuperación y restablecimiento de contraseña.

**Usuarios que acceden:** no autenticados (rutas públicas). Una vez autenticado, el usuario accede a las rutas protegidas del feature `wallet`.

**Bounded contexts del backend consumidos:** BC-01 Identity (`identity-service`).

---

## 2. Prerrequisitos

- `identity-service` activo en K3d dev o accesible en `http://localhost:8081`.
- `frontend/pagofacil-web/.env.local` con `NEXTAUTH_URL`, `NEXTAUTH_SECRET`, `COGNITO_ISSUER_URI` y `NEXT_PUBLIC_API_BASE_URL`.
- Etapa 2b completa (pipeline CI para el frontend).

---

## 3. Rutas y Páginas

| Path | Tipo | Componente de página | Descripción |
|---|---|---|---|
| `/login` | Público | `app/login/page.tsx` | Formulario de inicio de sesión (primer factor) |
| `/login/mfa` | Público | `app/login/mfa/page.tsx` | Verificación del segundo factor MFA |
| `/register` | Público | `app/register/page.tsx` | Formulario de registro de nuevo usuario |
| `/password/recover` | Público | `app/password/recover/page.tsx` | Solicitar recuperación de contraseña |
| `/password/reset` | Público | `app/password/reset/page.tsx` | Restablecer contraseña con token |

Todos son **CSR** (Client Side Rendering) con formularios reactivos. No requieren SSR ni ISR.

> **Regla TDD:** cada schema Zod, hook y componente de este feature tiene su prueba Vitest especificada en la Sección 9, escrita y vista fallar **ANTES** de implementar el artefacto. Los flujos E2E (Sección 10) se describen antes de integrar el feature y se validan al final.

---

## 4. Componentes — _test-first_

| Componente | Tipo | Responsabilidad |
|---|---|---|
| `LoginForm` | Client Component | Campos email + contraseña; submit → llama al hook `useLogin`; muestra error de credenciales o redirecciona a MFA |
| `MfaVerifyForm` | Client Component | Campo código 6 dígitos; submit → llama al hook `useMfaVerify`; redirecciona al dashboard en éxito |
| `RegisterForm` | Client Component | Campos email, nombre completo, tipo documento, número documento, contraseña; validación Zod en tiempo real; submit → llama a `useRegister` |
| `PasswordRecoverForm` | Client Component | Campo email; submit → llama a `usePasswordRecover`; muestra mensaje de confirmación |
| `PasswordResetForm` | Client Component | Campos nueva contraseña + confirmación + token (query param); submit → llama a `usePasswordReset` |
| `AuthLayout` | Server Component | Layout compartido de las páginas de auth: logo, centrado vertical, sin barra de navegación |

---

## 5. Integración con API (TanStack Query) — _test-first_

| Hook | Endpoint | Tipo | Descripción | Caché |
|---|---|---|---|---|
| `useLogin` | `POST /v1/identity/auth/login` | `useMutation` | Primer factor; en éxito guarda `mfaSessionToken` en Zustand y navega a `/login/mfa` | No cache |
| `useMfaVerify` | `POST /v1/identity/auth/mfa/verify` | `useMutation` | Segundo factor; en éxito llama a `signIn` de NextAuth con el `accessToken` | No cache |
| `useRegister` | `POST /v1/identity/users` | `useMutation` | Registro de usuario; en éxito navega a `/login` con mensaje de confirmación | No cache |
| `usePasswordRecover` | `POST /v1/identity/auth/password/recover-request` | `useMutation` | Solicitar token; siempre muestra éxito (no revela si el email existe) | No cache |
| `usePasswordReset` | `POST /v1/identity/auth/password/reset` | `useMutation` | Restablecer con token; en éxito navega a `/login` | No cache |
| `useKycStatus` | `GET /v1/identity/users/me/kyc-status` | `useQuery` | Consultar estado KYC después del registro | `staleTime: 30s` |

---

## 6. Estado Global (Zustand)

| Slice | Estado | Acciones |
|---|---|---|
| `authSlice` | `mfaSessionToken: string \| null` | `setMfaSessionToken(token)`, `clearMfaSessionToken()` |

El `mfaSessionToken` persiste solo en memoria durante el flujo MFA (entre `/login` y `/login/mfa`). Se limpia al completar la autenticación o navegar fuera.

---

## 7. Esquemas de Validación (Zod) — _test-first_

```typescript
// schemas/auth.ts
const loginSchema = z.object({
  email: z.string().email("Email inválido"),
  password: z.string().min(1, "Contraseña requerida")
});

const mfaVerifySchema = z.object({
  mfaCode: z.string().length(6, "El código debe tener 6 dígitos").regex(/^\d+$/, "Solo dígitos")
});

const registerSchema = z.object({
  email: z.string().email("Email inválido").max(320),
  fullName: z.string().min(1).max(255),
  documentType: z.enum(["DNI", "PASSPORT", "CE"]),
  documentNumber: z.string().min(1).max(50),
  password: z.string().min(10, "Mínimo 10 caracteres"),
  passwordConfirm: z.string()
}).refine(d => d.password === d.passwordConfirm, {
  message: "Las contraseñas no coinciden",
  path: ["passwordConfirm"]
});

const passwordResetSchema = z.object({
  newPassword: z.string().min(10, "Mínimo 10 caracteres"),
  newPasswordConfirm: z.string()
}).refine(d => d.newPassword === d.newPasswordConfirm, {
  message: "Las contraseñas no coinciden",
  path: ["newPasswordConfirm"]
});
```

---

## 8. Autenticación y Autorización

- Todas las rutas de este feature son **públicas** — no requieren JWT.
- NextAuth.js gestiona la sesión del usuario post-autenticación MFA.
- El `accessToken` JWT de Cognito recibido del `identity-service` se inyecta en la sesión NextAuth y se adjunta al header `Authorization: Bearer <token>` en las llamadas a APIs protegidas.
- El middleware NextAuth redirige a `/login` si un usuario no autenticado intenta acceder a rutas protegidas (`/dashboard`, `/audit/**`).
- Expiración del token: el middleware verifica `exp` del JWT y redirige a `/login` si expiró.

---

## 9. Especificación TDD — Pruebas Unitarias (Vitest)

> Cada prueba se escribe y se ve **fallar (Red)** antes de implementar el artefacto que la hace **pasar (Green)**, seguido de **Refactor**.

### Schemas Zod

| Archivo de test | Caso de test | Schema de Sección 7 |
|---|---|---|
| `schemas/auth.test.ts` | `loginSchema válido con email y contraseña correctos` | `loginSchema` |
| `schemas/auth.test.ts` | `loginSchema inválido — email sin @` | `loginSchema` |
| `schemas/auth.test.ts` | `mfaVerifySchema inválido — código de 5 dígitos` | `mfaVerifySchema` |
| `schemas/auth.test.ts` | `mfaVerifySchema inválido — código con letras` | `mfaVerifySchema` |
| `schemas/auth.test.ts` | `registerSchema válido — todos los campos correctos` | `registerSchema` |
| `schemas/auth.test.ts` | `registerSchema inválido — contraseñas no coinciden` | `registerSchema` |
| `schemas/auth.test.ts` | `registerSchema inválido — contraseña menor a 10 caracteres` | `registerSchema` |
| `schemas/auth.test.ts` | `passwordResetSchema inválido — contraseñas no coinciden` | `passwordResetSchema` |

### Hooks (MSW)

| Archivo de test | Escenario mockeado (MSW) | Hook de Sección 5 |
|---|---|---|
| `hooks/useLogin.test.ts` | `POST /v1/identity/auth/login` → 200 con `mfaSessionToken` | `useLogin` |
| `hooks/useLogin.test.ts` | `POST /v1/identity/auth/login` → 401 | `useLogin` (error handling) |
| `hooks/useLogin.test.ts` | `POST /v1/identity/auth/login` → 423 (cuenta bloqueada) | `useLogin` |
| `hooks/useMfaVerify.test.ts` | `POST /v1/identity/auth/mfa/verify` → 200 con `accessToken` | `useMfaVerify` |
| `hooks/useMfaVerify.test.ts` | `POST /v1/identity/auth/mfa/verify` → 401 | `useMfaVerify` |
| `hooks/useRegister.test.ts` | `POST /v1/identity/users` → 201 | `useRegister` |
| `hooks/useRegister.test.ts` | `POST /v1/identity/users` → 409 (email duplicado) | `useRegister` |

### Componentes (React Testing Library)

| Archivo de test | Interacción / estado validado | Componente de Sección 4 |
|---|---|---|
| `components/LoginForm.test.tsx` | Renderiza campos email y contraseña vacíos | `LoginForm` |
| `components/LoginForm.test.tsx` | Muestra error de validación Zod si email inválido al submit | `LoginForm` |
| `components/LoginForm.test.tsx` | Muestra mensaje de error 401 de la API | `LoginForm` |
| `components/MfaVerifyForm.test.tsx` | Renderiza campo de código de 6 dígitos | `MfaVerifyForm` |
| `components/MfaVerifyForm.test.tsx` | Deshabilita submit mientras está cargando | `MfaVerifyForm` |
| `components/RegisterForm.test.tsx` | Renderiza todos los campos y select de documentType | `RegisterForm` |
| `components/RegisterForm.test.tsx` | Muestra error en tiempo real si contraseñas no coinciden | `RegisterForm` |

### Slices Zustand

| Archivo de test | Acción / transición | Slice de Sección 6 |
|---|---|---|
| `store/authSlice.test.ts` | `setMfaSessionToken` guarda el token en estado | `authSlice` |
| `store/authSlice.test.ts` | `clearMfaSessionToken` deja estado en null | `authSlice` |

**Umbral de cobertura del feature:** ≥ 80%.

---

## 10. Pruebas E2E (Playwright, ATDD)

> Los siguientes flujos se describen **antes** de integrar el feature y se validan al final como criterio de aceptación.

| Nombre del test | Flujo descrito | Precondiciones | Resultado esperado |
|---|---|---|---|
| `auth-register-and-login.spec.ts` | Usuario se registra → recibe confirmación → inicia sesión → verifica MFA → llega a dashboard | Usuario no existe en sistema | Redirigido a `/dashboard` con sesión activa |
| `auth-invalid-login.spec.ts` | Usuario ingresa contraseña incorrecta 3 veces | Usuario existe y está activo | Tercer intento muestra error de bloqueo inminente |
| `auth-password-recovery.spec.ts` | Usuario solicita recuperación → recibe link (simulado en dev) → restablece contraseña → inicia sesión con nueva contraseña | Usuario activo existe | Login exitoso con nueva contraseña |
| `auth-mfa-invalid-code.spec.ts` | Usuario pasa primer factor → ingresa código MFA inválido | Usuario con MFA activo | Error de código inválido, sin redirigir al dashboard |

---

## 11. Criterios de Aceptación

- [ ] Cada schema, hook y componente tuvo su prueba escrita primero (Red) y luego pasó (Green).
- [ ] `npm run test` finaliza en verde.
- [ ] La cobertura del feature ≥ 80%.
- [ ] Los flujos E2E de la Sección 10 pasan en Playwright contra el ambiente dev.
- [ ] `POST /v1/identity/users` + formulario de registro crea usuario con `accountStatus: PENDIENTE_KYC`.
- [ ] Inicio de sesión exitoso redirige a `/login/mfa`; código MFA correcto redirige a `/dashboard`.
- [ ] Cuenta bloqueada muestra mensaje claro sin revelar el motivo exacto.
- [ ] El flujo de recuperación de contraseña no revela si el email existe o no.
- [ ] El pipeline CI despliega el frontend a Vercel preview URL correctamente.
