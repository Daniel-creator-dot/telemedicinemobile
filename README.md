# Digi Health

Connected digital healthcare for Ghana: patients, doctors, triage, labs, imaging, pharmacies, medical operations, corporate schemes, insurers, finance and administrators — one longitudinal record.

Built by Bytz Buddiz. Flutter client + Express/Postgres API. Video visits use Jitsi.

## How to run

### API

```bash
cd server
cp .env.example .env   # or create .env
npm install
npm run dev
```

The server binds `0.0.0.0:$PORT` (default `5000`) for local and Render.

Required environment:

| Variable | Purpose |
| --- | --- |
| `DATABASE_URL` | Postgres connection string |
| `JWT_SECRET` | Session signing secret |
| `PORT` | HTTP port (Render sets this) |
| `FIREBASE_SERVICE_ACCOUNT_KEY` | Optional JSON for FCM push |
| `NODE_ENV` | Set `production` to hide debug OTPs |
| `OPENAI_API_KEY` | Optional. If unset, clinical AI assist uses rule-based drafts |
| `OPENAI_MODEL` | Optional model name (default `gpt-4o-mini`) |

SMS credentials live in the `settings` table and are never returned to non-admin clients. Configure them from the admin console after login.

### Flutter app

```bash
flutter pub get
flutter run --dart-define=API_URL=http://localhost:5000
```

Defaults if `API_URL` is omitted:

- Web / desktop: `http://localhost:5000`
- Android emulator: `http://10.0.2.2:5000`

Physical devices need a reachable host, for example:

```bash
flutter run --dart-define=API_URL=http://192.168.1.20:5000
```

## Roles

Sign in with a seeded or admin-created account. Patient self-registration is OTP-only.

| Role | Username (typical seed) | Home |
| --- | --- | --- |
| Patient | phone + OTP register | Consult Now, book, video, chat, Rx, records, tracker |
| Doctor | created by admin | Queue, video consult, SOAP, e-prescribe, referrals |
| Nurse / triage | `nurse` | Pre-consult triage and urgency |
| Medical operations | `medops` | Command centre, queue, follow-ups |
| Lab technician | `labtech` | Lab request lifecycle + result return |
| Pharmacy | partner staff | E-prescription fulfilment |
| Imaging | partner staff | Imaging referrals + reports |
| Corporate | scheme admin | Eligibility and utilization (no clinical notes) |
| Insurance | insurer desk | Preauth and claims |
| Finance | finance | Collections and settlements |
| Admin | `admin` | Staff, doctors, settings, analytics |

Default local passwords (change in production): `admin` / `admin`, `nurse` / `nurse123`, `medops` / `ops123`, `labtech` / `labtech123`.

## Product surface

- **Patient:** OTP onboarding, medical profile, doctor directory, book + Consult Now, Jitsi video, in-visit chat, prescriptions, labs/imaging, health journey, document vault, health tracker, notifications, family/dependents, chronic care programs, assistive symptom helper
- **Clinician:** queue cockpit (next patient, SOAP, Rx, chat, video, end visit), assistive SOAP draft, referrals
- **Network:** nurse triage, lab, pharmacy, imaging, medical operations
- **Business:** corporate, insurance, finance/billing (phase 3 APIs)
- **Admin:** staff registry, clinic/SMS settings (API key masked), ops snapshot from authenticated APIs

### Phase 4 flows

- **Family / dependents:** Patient → Family. Add a child/spouse/parent (creates a patient record, no login). Book or Consult Now on their behalf. Appointments stay scoped to the guardian account.
- **Care programs:** Patient → Care programs. Enroll in hypertension, diabetes, asthma, sickle cell, or antenatal. Mark daily/weekly tasks; reminders go to the existing notifications inbox. Not a diagnosis.
- **Clinical AI assist:** Doctor SOAP dialog → “Draft SOAP (assistive)”. Patient → Symptom helper. Works without an LLM key (templated from notes/vitals). If `OPENAI_API_KEY` is set, a richer draft is attempted. Always labeled assistive; never a diagnosis; no HIPAA claim.
- **Vault:** Rx, labs, imaging, letters, plus document *metadata* you add (title, source, notes). This API does not store file bytes (Render disk is ephemeral).

Video rooms use unguessable Jitsi names (`digihealth-` + random hex). Visit pay is **simulated** and labeled as such. SMS never includes diagnoses. Settings GET never returns a raw SMS API key.

This is not a HIPAA-certified deployment. Use TLS in production, keep `JWT_SECRET` private, and treat all clinical data as confidential.

## Layout

- `lib/` — Digi Health Flutter app
- `server/` — Express API (`index.ts` plus `phase1.ts` / `phase2.ts` / `phase3.ts` / `clinical.ts` / `phase4.ts` / `authz.ts`)
- `mobile/` — leftover delivery prototype; not the telemedicine product
