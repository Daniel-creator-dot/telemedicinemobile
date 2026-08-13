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

**Live API:** https://telemedicine-server-l2bj.onrender.com  
**Health:** https://telemedicine-server-l2bj.onrender.com/health

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
| `PAYSTACK_PUBLIC_KEY` | Same `pk_test_` / `pk_live_` as Bytz Go (or set in Admin → Settings) |
| `PAYSTACK_SECRET_KEY` | Matching `sk_test_` / `sk_live_` secret |
| `PAYSTACK_CALLBACK_URL` | Optional API origin for Paystack return (`/api/paystack/callback`) |

SMS credentials live in the `settings` table and are never returned to non-admin clients. Configure them from the admin console after login.

### Flutter app

```bash
flutter pub get
flutter run
```

The app talks to the live Render API by default (`https://telemedicine-server-l2bj.onrender.com`). Override for local work:

```bash
flutter run --dart-define=API_URL=http://localhost:5000
```

Android emulator to a local API: `--dart-define=API_URL=http://10.0.2.2:5000`.

## Roles

Sign in with a seeded or admin-created account. Patient self-registration is OTP-only.

| Role | Username (typical seed) | Home |
| --- | --- | --- |
| Patient | phone + OTP register | Consult Now, book, video, chat, Rx, records, tracker |
| Doctor | `dr_appiah` / `staff123` (also `dr_mensah`, `dr_doe`) | Queue, video consult, SOAP, e-prescribe, referrals |
| Nurse / triage | `nurse` | Pre-consult triage and urgency |
| Medical operations | `medops` | Command centre, queue, follow-ups |
| Lab technician | `labtech` | Lab request lifecycle + result return |
| Pharmacy | partner staff | E-prescription fulfilment |
| Imaging | partner staff | Imaging referrals + reports |
| Corporate | scheme admin | Eligibility and utilization (no clinical notes) |
| Insurance | insurer desk | Preauth and claims |
| Finance | finance | Collections and settlements |
| Hospital | `hospital` / `hosp123` | Inbound specialist referrals |
| Admin | `admin` | Staff, doctors, settings, analytics, support, national net |
| Support desk | `support` | Same as admin ticket queue (`support` / `support123`) |

Default local passwords (change in production): `admin`/`admin`, `nurse`/`nurse123`, `medops`/`ops123`, `labtech`/`labtech123`, `hospital`/`hosp123`, `support`/`support123`.

## Five phases (one record)

| Phase | What it is | In the app |
| --- | --- | --- |
| 1 Consult | Book, Consult Now, video, chat, SOAP | Patient home, doctor queue |
| 2 Network | Labs, imaging, pharmacy, referrals — closed loop | Patient → Care phases |
| 3 Cover | Eligibility, Paystack copay, Classic–Diamond membership | Payments, Membership |
| 4 Household | Family, programs, vault, assistive helper | Family, Care programs |
| 5 Nation | 16 regions, follow-up, risk alerts, audit | Ghana network, Care phases |

Open **Patient → Care phases** for live counts on all five.

## Product surface

- **Patient:** OTP onboarding, medical profile, doctor directory, book + Consult Now, Jitsi video, in-visit chat, prescriptions, labs/imaging, health journey, document vault, health tracker, notifications, family/dependents, chronic care programs, assistive symptom helper, Ghana partner network
- **Clinician:** queue cockpit (next patient, SOAP, Rx, chat, video, end visit), assistive SOAP draft, referrals
- **Network:** nurse triage, lab, pharmacy, imaging, hospital desk, medical operations
- **Business:** corporate, insurance, finance/billing (phase 3 APIs)
- **Admin:** staff registry, clinic/SMS settings (API key masked), ops snapshot from authenticated APIs

### Phase 4 flows

- **Family / dependents:** Patient → Family. Add a child/spouse/parent (creates a patient record, no login). Book or Consult Now on their behalf. Appointments stay scoped to the guardian account.
- **Care programs:** Patient → Care programs. Enroll in hypertension, diabetes, asthma, sickle cell, or antenatal. Mark daily/weekly tasks; reminders go to the existing notifications inbox. Not a diagnosis.
- **Clinical AI assist:** Doctor SOAP dialog → “Draft SOAP (assistive)”. Patient → Symptom helper. Works without an LLM key (templated from notes/vitals). If `OPENAI_API_KEY` is set, a richer draft is attempted. Always labeled assistive; never a diagnosis; no HIPAA claim.
- **Vault:** Rx, labs, imaging, letters from visits, plus photos/PDFs you attach (up to 2 MB). Files are stored in Postgres so they survive Render’s ephemeral disk.

Video rooms use unguessable Jitsi names (`digihealth-` + random hex). Visit copay uses the same Paystack initialize/verify API as Bytz Go (`PAYSTACK_PUBLIC_KEY` / `PAYSTACK_SECRET_KEY`, GHS, card / MoMo / bank). SMS never includes diagnoses. Settings GET never returns a raw SMS or Paystack secret key.

This is not a HIPAA-certified deployment. Use TLS in production, keep `JWT_SECRET` private, and treat all clinical data as confidential.

## Layout

- `lib/` — Digi Health Flutter app
- `server/` — Express API (`index.ts` plus `phase1.ts`–`phase5.ts`, `phases.ts`, `clinical.ts`, `authz.ts`, `paystack.ts`, `membership.ts`)
- `mobile/` — leftover delivery prototype; not the telemedicine product

### Phase 5 — national scale

- **Ghana network:** Patient → Ghana network. Coverage across all 16 regions, nearest pharmacy/lab/imaging/hospital (region centroid or `lat`/`lng` query).
- **Medical ops:** National coverage, open risk alerts, append-only audit of mutating API calls.
- **Matching:** Lab/imaging/pharmacy assignment uses region plus GPS distance when coordinates exist.
- **Tenant isolation:** Corporate and insurance desks only see their linked organisation (`org_accounts`).
- **Family charts:** Open a dependent’s visits, programs, vault, and alerts (guardian-scoped).
- **Doctor enroll:** SOAP dialog → Enroll in care program.
- **Risk alerts:** Rule-based from tracker (high BP/glucose) and overdue program tasks. Labeled assistive, not a diagnosis.
- **Consents:** `POST /api/consents/me` for telemedicine, data, communication, sharing, AI assist.

This is still not a production national deployment: Jitsi is public-hosted with unguessable room names. Paystack keys must be set (env or Admin → Settings) before live collection. Vault files live in Postgres (2 MB cap), not object storage.

### Completeness pass

- **Payments & cover:** Patient → Payments. Eligibility plus Paystack receipts (GHS). Same initialize + verify flow as Bytz Go.
- **Membership:** Patient → Membership. Classic, Premium, Gold, Diamond (monthly or yearly). Lowers visit copay, adds household dependents, and shortens the live queue. Paid with the same Paystack API.
- **Follow-up care:** Closed-loop review dates from SOAP.
- **Help / support desk:** Patients open tickets; ops and admin resolve them.
- **Consents:** Toggle telemedicine, data, messaging, sharing, and assistive AI — timestamped.
- **Visual system:** Paper canvas, forest primary, gold secondary, Source Serif headlines + DM Sans UI. Quiet bottom navigation. Editorial login and launch copy. Nurse, pharmacy, imaging, and ops desks use the same chrome.
- **Directory:** Filter clinicians by language (English, Twi, Ga, Ewe, Hausa).
- **Hospital desk:** `hospital` / `hosp123` sees inbound network referrals.
- **Follow-up:** Book the review visit from the follow-up list.

Default local extra: `support` / `support123`.
