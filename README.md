# Digi Health Telemedicine

Flutter mobile app with Node/Express API for telemedicine appointments, secure chat, prescriptions, and Paystack copay payments.

## Structure

| Path | Description |
|------|-------------|
| `lib/` | Flutter app (patient, doctor, admin, lab technician) |
| `server/` | Express API + PostgreSQL |
| `assets/` | Branding and logos |

## Quick start

### Backend

```bash
cd server
cp .env.example .env   # set DATABASE_URL, JWT_SECRET, optional PAYSTACK_SECRET_KEY
npm install
npm run dev
```

### Flutter app

```bash
flutter pub get
flutter run
```

API base URL is configured in `lib/core/api_client.dart` (default: Render deployment).

## Demo accounts (after `npm run seed` in server)

| Role | Username | Password |
|------|----------|----------|
| Admin | admin | admin123 |
| Doctor | dr_appiah | staff123 |
| Lab tech | labtech | labtech123 |

Register new patients from the app sign-up flow.

## Features

- Role-based routing (patient, doctor, admin, lab technician)
- Appointment booking with calendar view
- Telemedicine video links (Jitsi) after copay payment
- Paystack checkout (MoMo/card) when `PAYSTACK_SECRET_KEY` is set; mock pay otherwise
- Secure patient–doctor chat
- Prescriptions and consultation history
- Firebase push + local appointment reminders

## Paystack

Set in `server/.env`:

```
PAYSTACK_SECRET_KEY=sk_test_...
PAYSTACK_CALLBACK_URL=https://standard.paystack.co/close
```

Telemedicine visit copay: **GHS 50.00**

## Deploy to Render

1. Push this repo to GitHub/GitLab.
2. In [Render Dashboard](https://dashboard.render.com) → **New** → **Blueprint** → connect the repo.
3. Render reads `render.yaml` and creates the API + Postgres database.
4. Set `PAYSTACK_SECRET_KEY` in the service environment when ready for live payments.
5. Update `lib/core/api_client.dart` `baseUrl` to your Render API URL if it differs from the default.

Existing deployment: `https://graprimeback-wniz.onrender.com` — redeploy that service from its connected repo or migrate to this Blueprint.

Health check: `GET /health`
