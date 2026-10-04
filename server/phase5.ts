import type { Express, Response } from 'express';
import { query } from './db';
import {
  authenticate,
  AuthedRequest,
  canAccessPatient,
  ADMIN_OPS,
  CLINICAL_STAFF,
  requireRoles,
} from './authz';
import { getAccessiblePatientIds, getPatientForUser } from './patients';

export const GHANA_REGIONS: {
  name: string;
  capital: string;
  lat: number;
  lng: number;
}[] = [
  { name: 'Greater Accra', capital: 'Accra', lat: 5.6037, lng: -0.187 },
  { name: 'Ashanti', capital: 'Kumasi', lat: 6.6885, lng: -1.6244 },
  { name: 'Western', capital: 'Takoradi', lat: 4.8845, lng: -1.7554 },
  { name: 'Western North', capital: 'Sefwi Wiawso', lat: 6.2059, lng: -2.4853 },
  { name: 'Central', capital: 'Cape Coast', lat: 5.1053, lng: -1.2466 },
  { name: 'Eastern', capital: 'Koforidua', lat: 6.094, lng: -0.2571 },
  { name: 'Volta', capital: 'Ho', lat: 6.6008, lng: 0.4713 },
  { name: 'Oti', capital: 'Dambai', lat: 8.0667, lng: 0.1833 },
  { name: 'Northern', capital: 'Tamale', lat: 9.4008, lng: -0.8393 },
  { name: 'Savannah', capital: 'Damongo', lat: 9.0833, lng: -1.8167 },
  { name: 'North East', capital: 'Nalerigu', lat: 10.5167, lng: -0.3667 },
  { name: 'Upper East', capital: 'Bolgatanga', lat: 10.7856, lng: -0.8514 },
  { name: 'Upper West', capital: 'Wa', lat: 10.0601, lng: -2.5099 },
  { name: 'Bono', capital: 'Sunyani', lat: 7.3349, lng: -2.3123 },
  { name: 'Bono East', capital: 'Techiman', lat: 7.5905, lng: -1.9298 },
  { name: 'Ahafo', capital: 'Goaso', lat: 6.8, lng: -2.5167 },
];

export function regionCentroid(region?: string | null) {
  if (!region) return null;
  const key = region.trim().toLowerCase();
  return (
    GHANA_REGIONS.find(
      (r) => r.name.toLowerCase() === key || r.capital.toLowerCase() === key
    ) || null
  );
}

export function haversineKm(
  a: { lat: number; lng: number },
  b: { lat: number; lng: number }
) {
  const toRad = (d: number) => (d * Math.PI) / 180;
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}

export async function writeAudit(entry: {
  userId?: number | null;
  role?: string | null;
  action: string;
  entity?: string | null;
  entityId?: string | number | null;
  meta?: Record<string, unknown>;
  ip?: string | null;
}) {
  try {
    await query(
      `INSERT INTO audit_log (user_id, role, action, entity, entity_id, meta, ip)
       VALUES ($1,$2,$3,$4,$5,$6::jsonb,$7)`,
      [
        entry.userId || null,
        entry.role || null,
        entry.action,
        entry.entity || null,
        entry.entityId != null ? String(entry.entityId) : null,
        JSON.stringify(entry.meta || {}),
        entry.ip || null,
      ]
    );
  } catch (err) {
    console.error('[audit] write failed');
  }
}

export function registerAuditMiddleware(app: Express) {
  app.use((req, res, next) => {
    res.on('finish', () => {
      const user = (req as AuthedRequest).user;
      if (!user) return;
      if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) return;
      if (!req.path.startsWith('/api/')) return;
      if (req.path.startsWith('/api/audit')) return;
      void writeAudit({
        userId: user.id,
        role: user.role,
        action: `${req.method} ${req.path}`,
        entity: req.path.split('/')[2] || 'api',
        entityId: (req.params as { id?: string })?.id || null,
        meta: { status: res.statusCode },
        ip: req.ip,
      });
    });
    next();
  });
}

export async function initPhase5Schema() {
  await query(`
    DO $$ BEGIN
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='lat') THEN
        ALTER TABLE partner_orgs ADD COLUMN lat DOUBLE PRECISION;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='lng') THEN
        ALTER TABLE partner_orgs ADD COLUMN lng DOUBLE PRECISION;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='hours') THEN
        ALTER TABLE partner_orgs ADD COLUMN hours VARCHAR(80);
      END IF;
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='partner_orgs' AND column_name='services') THEN
        ALTER TABLE partner_orgs ADD COLUMN services TEXT;
      END IF;
    END $$;
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS audit_log (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id),
      role VARCHAR(40),
      action VARCHAR(160) NOT NULL,
      entity VARCHAR(80),
      entity_id VARCHAR(40),
      meta JSONB DEFAULT '{}'::jsonb,
      ip VARCHAR(80),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS risk_alerts (
      id SERIAL PRIMARY KEY,
      patient_id INTEGER REFERENCES patients(id) ON DELETE CASCADE,
      severity VARCHAR(20) NOT NULL DEFAULT 'info',
      title VARCHAR(160) NOT NULL,
      detail TEXT,
      source VARCHAR(40) DEFAULT 'rules',
      status VARCHAR(20) DEFAULT 'open',
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);

  await query(`
    CREATE TABLE IF NOT EXISTS org_accounts (
      id SERIAL PRIMARY KEY,
      kind VARCHAR(20) NOT NULL,
      org_id INTEGER NOT NULL,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      UNIQUE(kind, user_id)
    )
  `);

  await seedNationalNetwork();
  await linkCommercialAccounts();
  await seedAdminAnalyticsDemo();
  console.log('Phase 5 schema ready');
}

/** Ensure national admin analytics has visits + claim rollups to demonstrate. */
async function seedAdminAnalyticsDemo() {
  try {
    const patient = await query(
      `SELECT id, full_name, phone_number, email FROM patients ORDER BY id ASC LIMIT 1`
    );
    if (!patient.rows[0]) return;
    const p = patient.rows[0];

    const doctor = await query(
      `SELECT id FROM doctors WHERE COALESCE(is_active, TRUE) = TRUE ORDER BY id ASC LIMIT 1`
    );
    const doctorId = doctor.rows[0]?.id || null;

    const recent = await query(
      `SELECT COUNT(*)::int AS n FROM appointments
       WHERE preferred_date >= CURRENT_DATE - INTERVAL '6 days'`
    );
    if (Number(recent.rows[0]?.n || 0) < 5 && doctorId) {
      const days: Array<{ offset: number; status: string; booking: string }> = [
        { offset: 0, status: 'queued', booking: 'consult_now' },
        { offset: 0, status: 'consulting', booking: 'consult_now' },
        { offset: 0, status: 'completed', booking: 'scheduled' },
        { offset: 1, status: 'completed', booking: 'scheduled' },
        { offset: 2, status: 'missed', booking: 'scheduled' },
        { offset: 3, status: 'completed', booking: 'scheduled' },
        { offset: 5, status: 'cancelled', booking: 'scheduled' },
      ];
      for (const d of days) {
        const code = `NA-${Date.now().toString(36).slice(-4)}${Math.random().toString(36).slice(2, 5)}`.toUpperCase();
        await query(
          `INSERT INTO appointments (
             appointment_id, patient_id, full_name, phone_number, email, doctor_id,
             preferred_date, preferred_time, status, priority, notes, service,
             is_telemedicine, booking_type, consult_type
           ) VALUES (
             $1,$2,$3,$4,$5,$6,
             CURRENT_DATE - ($7::int), '10:00:00', $8, 'normal',
             'National analytics demo visit', 'general consultation',
             TRUE, $9, 'general consultation'
           )
           ON CONFLICT (appointment_id) DO NOTHING`,
          [
            code,
            p.id,
            p.full_name,
            p.phone_number,
            p.email || null,
            doctorId,
            d.offset,
            d.status,
            d.booking,
          ]
        ).catch(() => null);
      }
    }

    const claimCount = await query(`SELECT COUNT(*)::int AS n FROM claims`).catch(() => ({
      rows: [{ n: 0 }],
    }));
    if (Number(claimCount.rows[0]?.n || 0) < 3) {
      const apt = await query(
        `SELECT id FROM appointments WHERE patient_id = $1 ORDER BY id DESC LIMIT 1`,
        [p.id]
      ).catch(() => ({ rows: [] as any[] }));
      const appointmentId = apt.rows[0]?.id || null;
      const demos: Array<{ amount: number; status: string; source: string }> = [
        { amount: 45, status: 'submitted', source: 'insurance' },
        { amount: 40, status: 'paid', source: 'insurance' },
        { amount: 30, status: 'approved', source: 'corporate' },
      ];
      for (const demo of demos) {
        const seq = await query(`SELECT nextval('claim_code_seq') AS n`).catch(() => null);
        if (!seq?.rows[0]) break;
        const claimCode = `CLM-NA-${String(seq.rows[0].n).padStart(5, '0')}`;
        await query(
          `INSERT INTO claims (claim_code, appointment_id, patient_id, source, amount, status, notes)
           VALUES ($1, $2, $3, $4, $5, $6, 'National admin analytics demo claim')`,
          [claimCode, appointmentId, p.id, demo.source, demo.amount, demo.status]
        ).catch(() => null);
      }
    }

    const alerts = await query(
      `SELECT COUNT(*)::int AS n FROM risk_alerts WHERE status = 'open'`
    ).catch(() => ({ rows: [{ n: 0 }] }));
    if (Number(alerts.rows[0]?.n || 0) === 0) {
      await query(
        `INSERT INTO risk_alerts (patient_id, severity, title, detail, source, status)
         VALUES ($1, 'warning', 'Demo elevated BP reading',
                 'Seeded for national admin analytics — assistive, not a diagnosis.',
                 'demo', 'open')`,
        [p.id]
      ).catch(() => null);
    }

    console.log('Admin national analytics demo ready (admin → Nation Pulse)');
  } catch (err) {
    console.warn('Admin analytics demo seed skipped', err);
  }
}

const NATIONAL_PARTNERS: {
  name: string;
  type: 'pharmacy' | 'laboratory' | 'imaging' | 'hospital';
  region: string;
  town: string;
  address: string;
  phone: string;
  hours: string;
  services: string;
}[] = GHANA_REGIONS.flatMap((r, i) => {
  const types: Array<'pharmacy' | 'laboratory' | 'imaging' | 'hospital'> = [
    'pharmacy',
    'laboratory',
    'imaging',
    'hospital',
  ];
  const type = types[i % 4];
  const labels = {
    pharmacy: `${r.capital} Community Pharmacy`,
    laboratory: `${r.capital} Diagnostic Lab`,
    imaging: `${r.capital} Imaging Centre`,
    hospital: `${r.name} Regional Hospital`,
  };
  return [
    {
      name: labels[type],
      type,
      region: r.name,
      town: r.capital,
      address: `Hospital Road, ${r.capital}`,
      phone: `0302${String(1000 + i).padStart(4, '0')}`,
      hours: '08:00–20:00',
      services:
        type === 'pharmacy'
          ? 'e-Rx collection, OTC, insurance desk'
          : type === 'laboratory'
            ? 'FBC, chemistry, malaria, HbA1c'
            : type === 'imaging'
              ? 'X-ray, ultrasound, CT (selected)'
              : 'OPD, emergency, specialist referral',
    },
  ];
});

async function seedNationalNetwork() {
  for (const p of NATIONAL_PARTNERS) {
    const centroid = regionCentroid(p.region);
    const existing = await query('SELECT id FROM partner_orgs WHERE name = $1 LIMIT 1', [p.name]);
    if (existing.rows[0]) {
      await query(
        `UPDATE partner_orgs
         SET lat = COALESCE(lat, $1), lng = COALESCE(lng, $2),
             hours = COALESCE(hours, $3), services = COALESCE(services, $4)
         WHERE id = $5`,
        [centroid?.lat || null, centroid?.lng || null, p.hours, p.services, existing.rows[0].id]
      );
      continue;
    }
    await query(
      `INSERT INTO partner_orgs (name, type, region, town, address, phone, lat, lng, hours, services, is_active)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10, TRUE)`,
      [
        p.name,
        p.type,
        p.region,
        p.town,
        p.address,
        p.phone,
        centroid?.lat || null,
        centroid?.lng || null,
        p.hours,
        p.services,
      ]
    );
  }

  await query(
    `UPDATE partner_orgs o
     SET lat = COALESCE(o.lat, r.lat), lng = COALESCE(o.lng, r.lng)
     FROM (VALUES
       ${GHANA_REGIONS.map((_, i) => `($${i * 3 + 1}, $${i * 3 + 2}::float, $${i * 3 + 3}::float)`).join(',')}
     ) AS r(name, lat, lng)
     WHERE o.region ILIKE r.name AND (o.lat IS NULL OR o.lng IS NULL)`,
    GHANA_REGIONS.flatMap((r) => [r.name, r.lat, r.lng])
  );
}

async function linkCommercialAccounts() {
  const corpUser = await query("SELECT id FROM users WHERE username = 'corporate' LIMIT 1");
  const insUser = await query("SELECT id FROM users WHERE username = 'insurance' LIMIT 1");
  const corp = await query("SELECT id FROM corporates ORDER BY id LIMIT 1");
  const ins = await query("SELECT id FROM insurers ORDER BY id LIMIT 1");
  if (corpUser.rows[0] && corp.rows[0]) {
    await query(
      `INSERT INTO org_accounts (kind, org_id, user_id) VALUES ('corporate', $1, $2)
       ON CONFLICT (kind, user_id) DO NOTHING`,
      [corp.rows[0].id, corpUser.rows[0].id]
    );
  }
  if (insUser.rows[0] && ins.rows[0]) {
    await query(
      `INSERT INTO org_accounts (kind, org_id, user_id) VALUES ('insurer', $1, $2)
       ON CONFLICT (kind, user_id) DO NOTHING`,
      [ins.rows[0].id, insUser.rows[0].id]
    );
  }
}

export async function commercialOrgId(kind: 'corporate' | 'insurer', userId: number) {
  const row = await query(
    'SELECT org_id FROM org_accounts WHERE kind = $1 AND user_id = $2 LIMIT 1',
    [kind, userId]
  );
  return row.rows[0]?.org_id ? Number(row.rows[0].org_id) : null;
}

function parseCoord(v: unknown) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

async function originForRequest(req: AuthedRequest) {
  const qLat = parseCoord(req.query.lat);
  const qLng = parseCoord(req.query.lng);
  if (qLat != null && qLng != null) return { lat: qLat, lng: qLng, source: 'device' as const };

  if (req.user?.role === 'patient') {
    const patient = await getPatientForUser(req.user.id);
    const c = regionCentroid(patient?.region || patient?.preferred_location || patient?.town);
    if (c) return { lat: c.lat, lng: c.lng, source: 'profile' as const };
  }
  const accra = GHANA_REGIONS[0];
  return { lat: accra.lat, lng: accra.lng, source: 'default' as const };
}

async function scanRisksForPatient(patientId: number) {
  const created: unknown[] = [];
  const trackers = await query(
    `SELECT * FROM health_measurements WHERE patient_id = $1 ORDER BY recorded_at DESC LIMIT 20`,
    [patientId]
  ).catch(() => ({ rows: [] as any[] }));

  for (const row of trackers.rows) {
    const kind = String(row.kind || '').toLowerCase();
    const value = Number(row.value_primary);
    if (!Number.isFinite(value)) continue;
    if ((kind.includes('bp') || kind.includes('systolic')) && value >= 160) {
      created.push(
        await upsertAlert(
          patientId,
          'high',
          'High blood pressure reading',
          `Latest ${kind} is ${value}. A clinician should review. Not a diagnosis.`,
          'tracker'
        )
      );
    }
    if ((kind.includes('glucose') || kind.includes('sugar')) && value >= 14) {
      created.push(
        await upsertAlert(
          patientId,
          'high',
          'High glucose reading',
          `Latest ${kind} is ${value}. Seek urgent care if you feel unwell. Not a diagnosis.`,
          'tracker'
        )
      );
    }
  }

  const overdue = await query(
    `SELECT t.title, p.condition FROM chronic_program_tasks t
     JOIN chronic_programs p ON p.id = t.program_id
     WHERE p.patient_id = $1 AND p.status = 'active' AND t.status = 'pending'
       AND t.due_on IS NOT NULL AND t.due_on < CURRENT_DATE
     LIMIT 8`,
    [patientId]
  ).catch(() => ({ rows: [] as any[] }));
  if (overdue.rows.length) {
    created.push(
      await upsertAlert(
        patientId,
        'medium',
        'Overdue care-program tasks',
        overdue.rows.map((r: any) => r.title).join(', '),
        'chronic'
      )
    );
  }
  return created.filter(Boolean);
}

async function upsertAlert(
  patientId: number,
  severity: string,
  title: string,
  detail: string,
  source: string
) {
  const existing = await query(
    `SELECT id FROM risk_alerts
     WHERE patient_id = $1 AND title = $2 AND status = 'open'
       AND created_at > NOW() - INTERVAL '2 days'
     LIMIT 1`,
    [patientId, title]
  );
  if (existing.rows[0]) return existing.rows[0];
  const row = await query(
    `INSERT INTO risk_alerts (patient_id, severity, title, detail, source)
     VALUES ($1,$2,$3,$4,$5) RETURNING *`,
    [patientId, severity, title, detail, source]
  );
  return row.rows[0];
}

export function registerPhase5Routes(app: Express) {
  app.get('/api/network/regions', authenticate, (_req, res) => {
    res.json(GHANA_REGIONS);
  });

  app.get('/api/network/coverage', authenticate, async (_req, res: Response) => {
    try {
      const partners = await query(
        `SELECT region, type, COUNT(*)::int AS count
         FROM partner_orgs WHERE is_active = TRUE
         GROUP BY region, type`
      );
      const doctors = await query(
        `SELECT 'National'::text AS region, COUNT(*)::int AS count FROM doctors WHERE is_active IS DISTINCT FROM FALSE`
      );
      const corporates = await query(
        `SELECT COALESCE(region, 'National') AS region, COUNT(*)::int AS count FROM corporates GROUP BY 1`
      ).catch(() => ({ rows: [] as any[] }));
      const insurers = await query(
        `SELECT COALESCE(region, 'National') AS region, COUNT(*)::int AS count FROM insurers GROUP BY 1`
      ).catch(() => ({ rows: [] as any[] }));

      const byRegion = GHANA_REGIONS.map((r) => {
        const rows = partners.rows.filter((p: any) => String(p.region || '').toLowerCase() === r.name.toLowerCase());
        const countFor = (type: string) =>
          rows.filter((p: any) => p.type === type).reduce((s: number, p: any) => s + Number(p.count || 0), 0);
        return {
          ...r,
          pharmacy: countFor('pharmacy'),
          laboratory: countFor('laboratory'),
          imaging: countFor('imaging'),
          hospital: countFor('hospital'),
          partners: rows.reduce((s: number, p: any) => s + Number(p.count || 0), 0),
        };
      });

      res.json({
        regions: byRegion,
        doctors: doctors.rows,
        corporates: corporates.rows,
        insurers: insurers.rows,
        totals: {
          partners: byRegion.reduce((s, r) => s + r.partners, 0),
          regions_with_partners: byRegion.filter((r) => r.partners > 0).length,
          regions: GHANA_REGIONS.length,
        },
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/network/directory', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const type = String(req.query.type || '');
      const region = String(req.query.region || '');
      const q = String(req.query.q || '').trim();
      const params: unknown[] = [];
      const where = ['is_active = TRUE'];
      if (type) {
        params.push(type);
        where.push(`type = $${params.length}`);
      }
      if (region) {
        params.push(`%${region}%`);
        where.push(`(region ILIKE $${params.length} OR town ILIKE $${params.length})`);
      }
      if (q) {
        params.push(`%${q}%`);
        where.push(`(name ILIKE $${params.length} OR services ILIKE $${params.length} OR town ILIKE $${params.length})`);
      }
      const rows = await query(
        `SELECT id, name, type, region, town, address, phone, lat, lng, hours, services
         FROM partner_orgs WHERE ${where.join(' AND ')} ORDER BY region, name`,
        params
      );
      res.json(rows.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/network/nearby', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const type = String(req.query.type || '');
      const origin = await originForRequest(req);
      const params: unknown[] = [];
      const where = ['is_active = TRUE', 'lat IS NOT NULL', 'lng IS NOT NULL'];
      if (type) {
        params.push(type);
        where.push(`type = $${params.length}`);
      }
      const rows = await query(
        `SELECT id, name, type, region, town, address, phone, lat, lng, hours, services
         FROM partner_orgs WHERE ${where.join(' AND ')}`,
        params
      );
      const ranked = rows.rows
        .map((p: any) => {
          const km = haversineKm(origin, { lat: Number(p.lat), lng: Number(p.lng) });
          return { ...p, distance_km: Math.round(km * 10) / 10, origin: origin.source };
        })
        .sort((a: any, b: any) => a.distance_km - b.distance_km)
        .slice(0, 40);
      res.json({ origin, results: ranked });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/network/national', authenticate, requireRoles(...ADMIN_OPS, 'admin'), async (_req, res) => {
    try {
      const [coverage, openAlerts, recentAudit, queue] = await Promise.all([
        query(`SELECT type, COUNT(*)::int AS count FROM partner_orgs WHERE is_active = TRUE GROUP BY type`),
        query(`SELECT severity, COUNT(*)::int AS count FROM risk_alerts WHERE status = 'open' GROUP BY severity`),
        query(`SELECT COUNT(*)::int AS count FROM audit_log WHERE created_at > NOW() - INTERVAL '24 hours'`),
        query(
          `SELECT status, COUNT(*)::int AS count FROM appointments
           WHERE created_at::date = CURRENT_DATE GROUP BY status`
        ).catch(() => ({ rows: [] as any[] })),
      ]);
      res.json({
        partners: coverage.rows,
        open_alerts: openAlerts.rows,
        audit_last_24h: recentAudit.rows[0]?.count || 0,
        appointments_today: queue.rows,
        regions: GHANA_REGIONS.length,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  /** Unified national admin analytics: visits + claims + partners + live queue. */
  app.get('/api/admin/analytics', authenticate, requireRoles('admin'), async (_req, res) => {
    try {
      const [
        visitsToday,
        visits7d,
        visitTrend,
        visitsByType,
        claimsByStatus,
        claimsBySource,
        claimsTotals,
        partnersByType,
        partnerMeta,
        queueLive,
        programs,
        alertMeta,
        audit24h,
      ] = await Promise.all([
        query(
          `SELECT status, COUNT(*)::int AS count FROM appointments
           WHERE preferred_date = CURRENT_DATE GROUP BY status`
        ),
        query(
          `SELECT
             COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE status = 'completed')::int AS completed,
             COUNT(*) FILTER (WHERE status IN ('pending','queued','approved','arrived','consulting'))::int AS open,
             COUNT(*) FILTER (WHERE status = 'missed')::int AS missed,
             COUNT(*) FILTER (WHERE status = 'cancelled')::int AS cancelled
           FROM appointments
           WHERE preferred_date >= CURRENT_DATE - INTERVAL '6 days'`
        ),
        query(
          `SELECT preferred_date::text AS day,
                  COUNT(*)::int AS total,
                  COUNT(*) FILTER (WHERE status = 'completed')::int AS completed
           FROM appointments
           WHERE preferred_date >= CURRENT_DATE - INTERVAL '6 days'
           GROUP BY preferred_date
           ORDER BY preferred_date ASC`
        ),
        query(
          `SELECT COALESCE(booking_type, 'scheduled') AS booking_type, COUNT(*)::int AS count
           FROM appointments
           WHERE preferred_date >= CURRENT_DATE - INTERVAL '6 days'
           GROUP BY 1 ORDER BY count DESC`
        ),
        query(
          `SELECT status, COUNT(*)::int AS count, COALESCE(SUM(amount),0)::float AS amount
           FROM claims GROUP BY status ORDER BY count DESC`
        ).catch(() => ({ rows: [] as any[] })),
        query(
          `SELECT COALESCE(source, 'unknown') AS source, COUNT(*)::int AS count,
                  COALESCE(SUM(amount),0)::float AS amount
           FROM claims GROUP BY 1 ORDER BY count DESC`
        ).catch(() => ({ rows: [] as any[] })),
        query(
          `SELECT
             COUNT(*)::int AS total,
             COUNT(*) FILTER (WHERE status IN ('submitted','queried'))::int AS open,
             COUNT(*) FILTER (WHERE status = 'paid')::int AS paid,
             COALESCE(SUM(amount) FILTER (WHERE status = 'paid' AND COALESCE(paid_at, submitted_at) > NOW() - INTERVAL '30 days'),0)::float AS paid_30d_amount
           FROM claims`
        ).catch(() => ({
          rows: [{ total: 0, open: 0, paid: 0, paid_30d_amount: 0 }],
        })),
        query(
          `SELECT type, COUNT(*)::int AS count FROM partner_orgs WHERE is_active = TRUE GROUP BY type`
        ),
        query(
          `SELECT
             COUNT(*)::int AS total,
             COUNT(DISTINCT region)::int AS regions_covered,
             COUNT(*) FILTER (WHERE COALESCE(network_status, 'online') = 'online')::int AS online,
             COUNT(*) FILTER (WHERE COALESCE(network_status, 'online') = 'busy')::int AS busy
           FROM partner_orgs WHERE is_active = TRUE`
        ).catch(() =>
          query(
            `SELECT COUNT(*)::int AS total, COUNT(DISTINCT region)::int AS regions_covered,
                    COUNT(*)::int AS online, 0::int AS busy
             FROM partner_orgs WHERE is_active = TRUE`
          )
        ),
        query(`
          SELECT
            (SELECT COUNT(*)::int FROM doctors
              WHERE is_active = TRUE
                AND COALESCE(is_online, FALSE) = TRUE
                AND last_seen_at IS NOT NULL
                AND last_seen_at > NOW() - INTERVAL '90 seconds') AS doctors_online,
            (SELECT COUNT(*)::int FROM appointments WHERE status = 'consulting') AS consulting_now,
            (SELECT COUNT(*)::int FROM appointments
              WHERE COALESCE(booking_type,'scheduled') = 'consult_now'
                AND status IN ('queued','pending','approved')) AS patients_waiting,
            (SELECT COALESCE(AVG(eta_minutes), 0)::float FROM appointments
              WHERE COALESCE(booking_type,'scheduled') = 'consult_now'
                AND status IN ('queued','pending')) AS avg_wait,
            (SELECT COUNT(*)::int FROM appointments
              WHERE preferred_date = CURRENT_DATE AND status = 'completed') AS completed_today,
            (SELECT COUNT(*)::int FROM appointments
              WHERE preferred_date = CURRENT_DATE AND status = 'missed') AS missed_today,
            (SELECT COUNT(*)::int FROM lab_requests
              WHERE status NOT IN ('completed','cancelled')) AS pending_labs,
            (SELECT COUNT(*)::int FROM scan_requests
              WHERE status NOT IN ('completed','cancelled')) AS pending_scans,
            (SELECT COUNT(*)::int FROM prescriptions
              WHERE COALESCE(dispense_status,'unsent') IN ('sent','received','preparing','ready')) AS pending_pharmacy,
            (SELECT COUNT(*)::int FROM referrals
              WHERE status NOT IN ('completed','declined')) AS open_referrals
        `),
        query(`SELECT COUNT(*)::int AS n FROM chronic_programs WHERE status = 'active'`).catch(() => ({
          rows: [{ n: 0 }],
        })),
        query(
          `SELECT severity, COUNT(*)::int AS count
           FROM risk_alerts WHERE status = 'open' GROUP BY severity`
        ).catch(() => ({ rows: [] as any[] })),
        query(
          `SELECT COUNT(*)::int AS count FROM audit_log WHERE created_at > NOW() - INTERVAL '24 hours'`
        ).catch(() => ({ rows: [{ count: 0 }] })),
      ]);

      const openAlerts = alertMeta.rows.reduce(
        (s: number, r: any) => s + Number(r.count || 0),
        0
      );

      res.json({
        generated_at: new Date().toISOString(),
        visits: {
          today: visitsToday.rows,
          last_7d: visits7d.rows[0] || {
            total: 0,
            completed: 0,
            open: 0,
            missed: 0,
            cancelled: 0,
          },
          trend_7d: visitTrend.rows,
          by_type: visitsByType.rows,
        },
        claims: {
          by_status: claimsByStatus.rows,
          by_source: claimsBySource.rows,
          ...(claimsTotals.rows[0] || { total: 0, open: 0, paid: 0, paid_30d_amount: 0 }),
        },
        partners: {
          by_type: partnersByType.rows,
          regions_total: GHANA_REGIONS.length,
          ...(partnerMeta.rows[0] || {
            total: 0,
            regions_covered: 0,
            online: 0,
            busy: 0,
          }),
        },
        queue: queueLive.rows[0] || {},
        programs: { active: programs.rows[0]?.n || 0 },
        alerts: {
          open: openAlerts,
          by_severity: alertMeta.rows.map((r: any) => ({
            severity: r.severity,
            count: Number(r.count || 0),
          })),
        },
        audit_last_24h: audit24h.rows[0]?.count || 0,
        note:
          'National admin rollup across clinic visits, insurer/corporate claims, partner network, and live queue. Tenant desks remain org-scoped.',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/audit', authenticate, requireRoles(...ADMIN_OPS), async (req: AuthedRequest, res) => {
    try {
      const limit = Math.min(200, Math.max(20, Number(req.query.limit) || 80));
      const rows = await query(
        `SELECT a.id, a.user_id, u.username, a.role, a.action, a.entity, a.entity_id, a.meta, a.ip, a.created_at
         FROM audit_log a
         LEFT JOIN users u ON u.id = a.user_id
         ORDER BY a.created_at DESC
         LIMIT $1`,
        [limit]
      );
      res.json(rows.rows);
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/consents/me', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.json([]);
      const rows = await query(
        `SELECT consent_type, version, accepted, accepted_at
         FROM consents WHERE patient_id = $1 ORDER BY accepted_at DESC`,
        [patient.id]
      );
      res.json(rows.rows);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/consents/me', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.status(400).json({ message: 'Complete your medical profile first.' });
      const type = String(req.body?.consent_type || '').trim();
      const allowed = ['telemedicine', 'data_processing', 'communication', 'sharing', 'ai_assist'];
      if (!allowed.includes(type)) return res.status(400).json({ message: 'Unknown consent type' });
      const accepted = req.body?.accepted !== false;
      const row = await query(
        `INSERT INTO consents (patient_id, consent_type, accepted, version)
         VALUES ($1,$2,$3,'1.0') RETURNING *`,
        [patient.id, type, accepted]
      );
      await writeAudit({
        userId: req.user!.id,
        role: req.user!.role,
        action: accepted ? 'consent.accept' : 'consent.revoke',
        entity: 'consents',
        entityId: row.rows[0].id,
        meta: { type },
      });
      res.status(201).json(row.rows[0]);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/risk-alerts', authenticate, async (req: AuthedRequest, res) => {
    try {
      let patientId = req.query.patient_id ? Number(req.query.patient_id) : null;
      if (req.user!.role === 'patient') {
        const ids = await getAccessiblePatientIds(req.user!.id);
        patientId = patientId && ids.includes(patientId) ? patientId : ids[0] || null;
      } else if (patientId && !(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      } else if (!patientId && CLINICAL_STAFF.includes(req.user!.role)) {
        const open = await query(
          `SELECT r.*, p.full_name, p.patient_code
           FROM risk_alerts r JOIN patients p ON p.id = r.patient_id
           WHERE r.status = 'open' ORDER BY r.created_at DESC LIMIT 50`
        );
        return res.json(open.rows);
      }
      if (!patientId) return res.json([]);
      const rows = await query(
        `SELECT * FROM risk_alerts WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 40`,
        [patientId]
      );
      res.json(rows.rows);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/risk-alerts/scan', authenticate, async (req: AuthedRequest, res) => {
    try {
      let patientId = req.body?.patient_id ? Number(req.body.patient_id) : null;
      if (req.user!.role === 'patient') {
        const mine = await getPatientForUser(req.user!.id);
        patientId = mine?.id || null;
      } else if (!patientId || !(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      if (!patientId) return res.status(400).json({ message: 'No patient' });
      const created = await scanRisksForPatient(patientId);
      res.json({ created: created.length, alerts: created });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.patch('/api/risk-alerts/:id', authenticate, requireRoles(...CLINICAL_STAFF), async (req: AuthedRequest, res) => {
    try {
      const status = req.body?.status === 'open' ? 'open' : 'closed';
      const row = await query(
        `UPDATE risk_alerts SET status = $1 WHERE id = $2 RETURNING *`,
        [status, req.params.id]
      );
      if (!row.rows[0]) return res.status(404).json({ message: 'Not found' });
      res.json(row.rows[0]);
    } catch (err) {
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.get('/api/family/:patientId/chart', authenticate, async (req: AuthedRequest, res) => {
    try {
      const patientId = Number(req.params.patientId);
      if (!(await canAccessPatient(req.user!, patientId))) {
        return res.status(403).json({ message: 'Forbidden' });
      }
      const [patient, appointments, programs, vault, alerts] = await Promise.all([
        query('SELECT id, full_name, patient_code, date_of_birth, sex, phone_number FROM patients WHERE id = $1', [
          patientId,
        ]),
        query(
          `SELECT id, appointment_date, appointment_time, status, reason, consult_type
           FROM appointments WHERE patient_id = $1 ORDER BY appointment_date DESC LIMIT 20`,
          [patientId]
        ),
        query(`SELECT id, condition, status, program_key, next_review FROM chronic_programs WHERE patient_id = $1`, [
          patientId,
        ]),
        query(
          `SELECT id, title, kind, source_label, created_at, file_name, byte_size, (content IS NOT NULL) AS has_file
           FROM vault_documents WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 20`,
          [patientId]
        ),
        query(`SELECT id, severity, title, status, created_at FROM risk_alerts WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 10`, [
          patientId,
        ]),
      ]);
      if (!patient.rows[0]) return res.status(404).json({ message: 'Not found' });
      res.json({
        patient: patient.rows[0],
        appointments: appointments.rows,
        programs: programs.rows,
        documents: vault.rows,
        alerts: alerts.rows,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });
}
