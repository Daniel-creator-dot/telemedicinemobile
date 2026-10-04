import type { Express, Response } from 'express';
import { query } from './db';
import { authenticate, AuthedRequest } from './authz';
import { getAccessiblePatientIds, getPatientForUser } from './patients';
import { getEligibility } from './phase3';
import { getActiveMembership } from './membership';

async function countWhere(sql: string, params: any[]) {
  const r = await query(sql, params).catch(() => ({ rows: [{ n: 0 }] }));
  return Number(r.rows[0]?.n || 0);
}

export function registerPhaseOverviewRoutes(app: Express) {
  app.get('/api/phases/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      const ids = req.user!.role === 'patient' ? await getAccessiblePatientIds(req.user!.id) : [];
      const patientId = patient?.id || ids[0] || null;
      if (!patientId) {
        return res.json({
          phases: [],
          loop: { labs: [], scans: [], referrals: [], prescriptions: [] },
          alerts: [],
          eligibility: null,
          membership: null,
        });
      }

      const idList = ids.length ? ids : [patientId];
      const [
        visits,
        queued,
        labsOpen,
        scansOpen,
        rxOpen,
        refsOpen,
        programs,
        family,
        followups,
        alertsOpen,
        membership,
        eligibility,
        loopLabs,
        loopScans,
        loopRefs,
        loopRx,
        alerts,
      ] = await Promise.all([
        countWhere(`SELECT COUNT(*)::int AS n FROM appointments WHERE patient_id = ANY($1)`, [idList]),
        countWhere(
          `SELECT COUNT(*)::int AS n FROM appointments WHERE patient_id = ANY($1) AND status IN ('queued','pending','approved','consulting')`,
          [idList]
        ),
        countWhere(
          `SELECT COUNT(*)::int AS n FROM lab_requests WHERE patient_id = ANY($1) AND COALESCE(status,'pending') NOT IN ('completed','cancelled')`,
          [idList]
        ),
        countWhere(
          `SELECT COUNT(*)::int AS n FROM scan_requests WHERE patient_id = ANY($1) AND COALESCE(status,'pending') NOT IN ('completed','cancelled')`,
          [idList]
        ),
        countWhere(
          `SELECT COUNT(*)::int AS n FROM prescriptions WHERE patient_id = ANY($1) AND COALESCE(dispense_status, 'unsent') NOT IN ('dispensed','cancelled')`,
          [idList]
        ),
        countWhere(
          `SELECT COUNT(*)::int AS n FROM referrals WHERE patient_id = ANY($1) AND COALESCE(status,'pending') NOT IN ('completed','cancelled')`,
          [idList]
        ),
        countWhere(`SELECT COUNT(*)::int AS n FROM chronic_programs WHERE patient_id = ANY($1) AND status = 'active'`, [
          idList,
        ]),
        countWhere(`SELECT COUNT(*)::int AS n FROM dependents WHERE guardian_patient_id = $1`, [patientId]),
        countWhere(
          `SELECT COUNT(*)::int AS n FROM consultations WHERE patient_id = ANY($1) AND follow_up_date IS NOT NULL AND follow_up_date >= CURRENT_DATE`,
          [idList]
        ).catch(() => 0),
        countWhere(`SELECT COUNT(*)::int AS n FROM risk_alerts WHERE patient_id = ANY($1) AND status = 'open'`, [idList]),
        getActiveMembership(patientId),
        getEligibility(patientId),
        query(
          `SELECT lr.*, o.name as partner_name FROM lab_requests lr LEFT JOIN partner_orgs o ON lr.partner_id = o.id
           WHERE lr.patient_id = ANY($1) ORDER BY lr.created_at DESC LIMIT 20`,
          [idList]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT sr.*, o.name as partner_name FROM scan_requests sr LEFT JOIN partner_orgs o ON sr.partner_id = o.id
           WHERE sr.patient_id = ANY($1) ORDER BY sr.created_at DESC LIMIT 20`,
          [idList]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT r.*, o.name as org_name FROM referrals r LEFT JOIN partner_orgs o ON r.to_org_id = o.id
           WHERE r.patient_id = ANY($1) ORDER BY r.created_at DESC LIMIT 20`,
          [idList]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT pr.*, o.name as pharmacy_name FROM prescriptions pr LEFT JOIN partner_orgs o ON pr.pharmacy_id = o.id
           WHERE pr.patient_id = ANY($1) ORDER BY pr.created_at DESC LIMIT 20`,
          [idList]
        ).catch(() => ({ rows: [] })),
        query(
          `SELECT * FROM risk_alerts WHERE patient_id = ANY($1) ORDER BY created_at DESC LIMIT 20`,
          [idList]
        ).catch(() => ({ rows: [] })),
      ]);

      const phases = [
        {
          id: 1,
          name: 'Consult',
          title: 'See a clinician',
          summary: 'Book, Consult Now, video, chat, and SOAP in one visit.',
          route: '/patient/consult-now',
          open: queued,
          total: visits,
          status: queued > 0 ? 'live' : visits > 0 ? 'active' : 'ready',
        },
        {
          id: 2,
          name: 'Network',
          title: 'Labs, imaging, pharmacy',
          summary: 'Closed-loop requests return to your record — not a separate app.',
          route: '/patient/journey',
          open: labsOpen + scansOpen + rxOpen + refsOpen,
          total: labsOpen + scansOpen + rxOpen + refsOpen,
          status: labsOpen + scansOpen + rxOpen + refsOpen > 0 ? 'live' : 'ready',
        },
        {
          id: 3,
          name: 'Cover',
          title: 'Insurance, corporate & membership',
          summary: eligibility.source === 'self_pay'
            ? `Self pay · GHS ${eligibility.copay}. Check insurance/corporate or join Classic–Diamond.`
            : `${eligibility.plan_name || eligibility.payer_name} · copay GHS ${eligibility.copay}`,
          route: '/patient/coverage',
          open: 0,
          total: membership || eligibility.eligible ? 1 : 0,
          status: eligibility.eligible || membership ? 'active' : 'ready',
        },
        {
          id: 4,
          name: 'Household',
          title: 'Family and long-term care',
          summary: 'Dependents, programs, vault, and assistive helper — one chart.',
          route: '/patient/family',
          open: programs,
          total: family,
          status: family + programs > 0 ? 'active' : 'ready',
        },
        {
          id: 5,
          name: 'Nation',
          title: 'Ghana network and alerts',
          summary: 'Sixteen regions, follow-up dates, and rule-based risk alerts.',
          route: '/patient/network',
          open: alertsOpen + followups,
          total: alertsOpen,
          status: alertsOpen > 0 ? 'live' : 'ready',
        },
      ];

      res.json({
        phases,
        loop: {
          labs: loopLabs.rows,
          scans: loopScans.rows,
          referrals: loopRefs.rows,
          prescriptions: loopRx.rows,
        },
        alerts: alerts.rows,
        eligibility,
        membership,
        followups_open: followups,
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });
}
