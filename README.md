# Medilynks

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
| Patient | OTP register, or demo `0241555000` / `patient123` | Consult Now, book, video, chat, Rx, records, tracker |
| Doctor | `dr_appiah` / `staff123` (also `dr_mensah`, `dr_doe`) | Queue, video consult, SOAP, e-prescribe, referrals |
| Nurse / triage | `nurse` | Pre-consult triage and urgency |
| Medical operations | `medops` / `ops123` | Command centre: queue assign, partner re-route (lab/imaging/pharmacy/referral) |
| Lab technician | `labtech` / `labtech123` | Lab request lifecycle + result return |
| Pharmacy | `pharmacy` / `pharm123` | E-prescription fulfilment |
| Imaging | `imaging` / `image123` | Imaging referrals + reports |
| Corporate | `corporate` / `corp123` | Staff roster, utilisation ledger, activate/suspend cover |
| Insurance | `insurance` / `insure123` | Claims desk: approve / query / deny / pay |
| Finance | `finance` / `fin123` | Receipts, reconcile, settlements |
| Hospital | `hospital` / `hosp123` | Network desk: inbound/outbound referrals, capacity, partners |
| Admin | `admin` / `admin` | Staff, doctors, clinic Pulse, **Nation Pulse** (visits/claims/partners/queue), support, national net |
| Support desk | `support` | Same as admin ticket queue (`support` / `support123`) |

Default local passwords (change in production): `admin`/`admin`, `nurse`/`nurse123`, `medops`/`ops123`, `labtech`/`labtech123`, `pharmacy`/`pharm123`, `imaging`/`image123`, `hospital`/`hosp123`, `support`/`support123`, `corporate`/`corp123`, `insurance`/`insure123`, `finance`/`fin123`.

## Five phases (one record)

| Phase | What it is | In the app |
| --- | --- | --- |
| 1 Consult | Book, Consult Now, video, chat, SOAP | Patient home, doctor queue |
| 2 Network | Labs, imaging, pharmacy, referrals — closed loop | Patient journey · Medical Ops board · partner desks |
| 3 Cover | Eligibility, Paystack copay, Classic–Diamond membership, corporate utilisation, insurer claims desk | Payments, Membership, Corporate, Insurance |
| 4 Household | Family, programs, vault, assistive helper | Family, Care programs |
| 5 Nation | 16 regions, follow-up, risk alerts, audit, **admin Nation Pulse** | Ghana network, Care phases, Admin → Nation Pulse |

Open **Patient → Care phases** for live counts on all five.

## Product surface

- **Patient:** OTP onboarding, medical profile, doctor directory, book + Consult Now, Jitsi video, in-visit chat, prescriptions, labs/imaging, health journey, document vault, health tracker, notifications, family/dependents, chronic care programs, assistive symptom helper, Ghana partner network
- **Clinician:** queue cockpit (next patient, SOAP, Rx, chat, video, end visit), assistive SOAP draft, referrals
- **Network:** nurse triage, lab, pharmacy, imaging, hospital desk, medical operations (queue assign + partner re-route)
- **Business:** corporate, insurance, finance/billing (phase 3 APIs)
- **Admin:** staff registry, clinic/SMS settings (API key masked), clinic Pulse, **Nation Pulse** national analytics, ops snapshot from authenticated APIs

### Phase 2 — closed-loop Medical Ops

- **Login:** `medops` / `ops123`
- **Overview:** live counts for waiting patients, open labs/scans/pharmacy/referrals, unassigned loops
- **Queue tab:** assign or reassign a clinician on Consult Now cases (`PATCH /api/queue/:id/assign`)
- **Network tab:** route or re-route lab, imaging, pharmacy, and hospital partners (`GET /api/ops/board`, `PATCH /api/ops/partner-assign`)
- Partner desks (`labtech`, `pharmacy`, `imaging`, `hospital`) still process fulfilment; Medical Ops owns routing when a facility is missing or wrong
- Demo seed creates a few unassigned open loops when the network queues are empty so assign can be demonstrated immediately

### Phase 3 — corporate utilisation desk

- **Login:** `corporate` / `corp123` (Ghana Ports Authority Benefits Desk; tenant-scoped via `org_accounts`)
- **Overview:** active/suspended headcount, billed YTD vs annual limit remaining, open/approved/paid claims, staff copay collected, spend by department
- **Roster tab:** enrol by patient ID + optional staff ID/department; **Suspend** / **Activate** cover (org-scoped)
- **Utilisation tab:** visit-level claim ledger (member, staff ID, covered vs copay, claim status) — **no clinical notes**
- Annual staff limits reduce covered amount once YTD corporate claims exhaust the scheme limit
- Demo seed creates open / approved / paid corporate claims when the utilisation queue is empty
- Patient attach remains on Patient → Payments / Coverage (`GPA-STAFF-9001`, `COCOA-STAFF-5001`, …)
- APIs: `GET /api/corporate/dashboard` (members + utilisation + stats), `POST /api/corporate/members`, `PATCH /api/corporate/members/:id`

### Phase 3 — insurance claims desk

- **Login:** `insurance` / `insure123` (Star Health Ghana; tenant-scoped via `org_accounts`)
- **Also:** `corporate` / `corp123` (GPA utilisation desk), `finance` / `fin123` (receipts + settlements)
- **Overview:** open / queried / approved / paid / denied claim counts plus pending preauths and active policies
- **Claims tab:** filter Open → Queried → Approved → Closed; **Approve**, **Query** (notes to patient), **Deny**, **Mark paid**
- **Preauths tab:** approve or deny pending pre-authorisations
- Each decision writes an in-app notification (and push when registered) for the patient
- Demo seed creates open + queried claims (and a pending preauth) when the insurer queue is empty
- Patient eligibility check / attach cover remains on Patient → Payments (`DEMO-SHG-1001`, `GPA-STAFF-9001`, …)

### Phase 3 — finance receipts desk

- **Login:** `finance` / `fin123`
- **Overview:** copay / covered totals, unreconciled vs reconciled counts, demo vs Paystack collections, doctor/partner pay due
- **Receipts tab:** filter Open → Reconciled → Demo → Paystack → Refunded; **Reconcile**, **Unreconcile**, **Refund**
- Demo gateway refunds stay local; live Paystack refs attempt `POST /refund` when keys are configured (seed `digihealth_finance_*` refs mark locally if Paystack declines)
- **Settlements tab:** run clinician/pharmacy settlements and mark paid (unchanged)
- Demo seed creates a few paid visit receipts (demo + Paystack-labeled, one refunded) when the payments table is sparse
- APIs: `GET /api/finance/dashboard` (includes `payments`), `PATCH /api/finance/payments/:id` (`reconcile` | `unreconcile` | `refund`)

### Phase 4 — hospital network desk

- **Login:** `hospital` / `hosp123` (linked to the first hospital partner org, typically Tamale Regional Hospital)
- **Overview:** inbound/outbound open counts, bed/ICU free vs total, regional partner online/busy
- **Inbound tab:** filter Open → Pending → Active → Closed; **Accept**, **In progress**, **Complete** (outcome notes), **Decline**
- **Outbound tab:** post a transfer by patient code to another hospital/lab/imaging facility; ledger of outbound referrals
- **Capacity tab:** publish bed/ICU stub board + facility status (`online` / `busy` / `offline`); partner board for the region
- Demo seed creates an inbound open referral, an outbound accepted transfer (when a second hospital exists), and default ward numbers
- APIs: `GET /api/hospital/desk`, `PATCH /api/hospital/capacity`, `POST /api/hospital/referrals/outbound`

### Phase 4 flows

- **Family / dependents:** Patient → Family. Add a child/spouse/parent (creates a patient record, no login). Book or Consult Now on their behalf. Appointments stay scoped to the guardian account.
- **Care programs:** Patient → Care programs. Enroll in hypertension, diabetes, asthma, sickle cell, or antenatal. Mark daily/weekly tasks; reminders go to the existing notifications inbox. Not a diagnosis.
- **Clinical AI assist:** Doctor SOAP dialog → “Draft SOAP (assistive)”. Patient → Symptom helper. Works without an LLM key (templated from notes/vitals). If `OPENAI_API_KEY` is set, a richer draft is attempted. Always labeled assistive; never a diagnosis; no HIPAA claim.
- **Vault:** Rx, labs, imaging, letters from visits, plus photos/PDFs you attach (up to 2 MB). Files are stored in Postgres so they survive Render’s ephemeral disk.
- **Hospital network desk:** see Phase 4 section above (`hospital` / `hosp123`).

Video rooms use unguessable Jitsi names (`digihealth-` + random hex). Visit copay uses the same Paystack initialize/verify API as Bytz Go (`PAYSTACK_PUBLIC_KEY` / `PAYSTACK_SECRET_KEY`, GHS, card / MoMo / bank). SMS never includes diagnoses. Settings GET never returns a raw SMS or Paystack secret key.

This is not a HIPAA-certified deployment. Use TLS in production, keep `JWT_SECRET` private, and treat all clinical data as confidential.

## Layout

- `lib/` — Medilynks Flutter app
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

### Phase 5 — Nation Pulse (admin analytics)

- **Login:** `admin` / `admin`
- **Open:** Admin → Launch pad → **Nation Pulse** (or `/admin/analytics`)
- **Overview:** 7-day visits, open claims, partner count, patients waiting now; programs, risk alerts, audit 24h
- **Visits tab:** daily trend, today-by-status, Consult Now vs scheduled mix
- **Claims tab:** cross-tenant rollup by status and source (insurance / corporate) — insurer/corporate desks stay org-scoped
- **Network tab:** partners by type + live queue (labs/scans/pharmacy/referrals)
- Demo seed adds a few recent visits, sample claims, and an open risk alert when sparse so the board is demonstrable immediately
- API: `GET /api/admin/analytics` (admin only)

This is still not a production national deployment: Jitsi is public-hosted with unguessable room names. Paystack keys must be set (env or Admin → Settings) before live collection. Vault files live in Postgres (2 MB cap), not object storage.

### Completeness pass

- **Payments & cover:** Patient → Payments. Eligibility plus Paystack receipts (GHS). Same initialize + verify flow as Bytz Go.
- **Membership:** Patient → Membership. Classic, Premium, Gold, Diamond (monthly or yearly). Lowers visit copay, adds household dependents, and shortens the live queue. Paid with the same Paystack API.
- **Follow-up care:** Closed-loop review dates from SOAP.
- **Help / support desk:** Patients open tickets; ops and admin resolve them.
- **Consents:** Toggle telemedicine, data, messaging, sharing, and assistive AI — timestamped.
- **Visual system:** Paper canvas, forest primary, gold secondary, Source Serif headlines + DM Sans UI. Quiet bottom navigation. Editorial login and launch copy. Nurse, pharmacy, imaging, and ops desks use the same chrome.
- **Directory:** Filter clinicians by language (English, Twi, Ga, Ewe, Hausa).
- **Hospital network desk:** `hospital` / `hosp123` — inbound/outbound referrals, bed/ICU capacity stub, partner status.
- **Nation Pulse:** `admin` / `admin` — national visits/claims/partners/queue analytics (`GET /api/admin/analytics`).
- **Follow-up:** Book the review visit from the follow-up list.

Default local extra: `support` / `support123`.
