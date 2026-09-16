import type { Express, Request, Response } from 'express';
import { query } from './db';
import { getPatientForUser } from './patients';
import {
  initializePaystackCheckout,
  paystackPaymentEmail,
  resolvePaymentVerification,
} from './paystack';

type AuthedRequest = Request & { user?: { id: number; username: string; role: string } };

export type MembershipTier = 'classic' | 'premium' | 'gold' | 'diamond';
export type MembershipPeriod = 'monthly' | 'yearly';

export type MembershipPlan = {
  tier: MembershipTier;
  name: string;
  tagline: string;
  monthlyGhs: number;
  yearlyGhs: number;
  copay: number;
  coveragePercent: number;
  dependents: number;
  queuePriority: 'Medium' | 'High' | 'Urgent';
  etaMinutes: number;
  recommended?: boolean;
  benefits: string[];
};

export const MEMBERSHIP_PLANS: MembershipPlan[] = [
  {
    tier: 'classic',
    name: 'Classic',
    tagline: 'A quieter way to start care',
    monthlyGhs: 49,
    yearlyGhs: 490,
    copay: 35,
    coveragePercent: 30,
    dependents: 1,
    queuePriority: 'Medium',
    etaMinutes: 12,
    benefits: [
      'Visit copay GHS 35 (from GHS 50)',
      'One dependent on your household chart',
      'Book, Consult Now, and video visits',
      'Records vault and receipts',
    ],
  },
  {
    tier: 'premium',
    name: 'Premium',
    tagline: 'For the household that stays in care',
    monthlyGhs: 99,
    yearlyGhs: 990,
    copay: 20,
    coveragePercent: 60,
    dependents: 2,
    queuePriority: 'High',
    etaMinutes: 10,
    benefits: [
      'Visit copay GHS 20',
      'Two dependents',
      'Priority live queue',
      'Care programs and symptom helper',
    ],
  },
  {
    tier: 'gold',
    name: 'Gold',
    tagline: 'The plan most families keep',
    monthlyGhs: 199,
    yearlyGhs: 1990,
    copay: 10,
    coveragePercent: 80,
    dependents: 4,
    queuePriority: 'High',
    etaMinutes: 7,
    recommended: true,
    benefits: [
      'Visit copay GHS 10',
      'Four dependents',
      'Faster live queue',
      'Follow-up visits at the same copay',
      'Priority support desk',
    ],
  },
  {
    tier: 'diamond',
    name: 'Diamond',
    tagline: 'Concierge care for the whole house',
    monthlyGhs: 399,
    yearlyGhs: 3990,
    copay: 0,
    coveragePercent: 100,
    dependents: 6,
    queuePriority: 'Urgent',
    etaMinutes: 4,
    benefits: [
      'Visit copay GHS 0 — covered',
      'Six dependents (household)',
      'Same-day queue, first to be seen',
      'Concierge nurse line in-app',
      'Every Medilynks care surface included',
    ],
  },
];

export function getPlan(tier: string): MembershipPlan | undefined {
  return MEMBERSHIP_PLANS.find((p) => p.tier === tier);
}

export function planPrice(plan: MembershipPlan, period: MembershipPeriod) {
  return period === 'yearly' ? plan.yearlyGhs : plan.monthlyGhs;
}

export async function initMembershipSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS memberships (
      id SERIAL PRIMARY KEY,
      patient_id INTEGER REFERENCES patients(id),
      user_id INTEGER REFERENCES users(id),
      tier VARCHAR(20) NOT NULL,
      period VARCHAR(20) NOT NULL DEFAULT 'monthly',
      status VARCHAR(20) NOT NULL DEFAULT 'active',
      amount DECIMAL(10,2) NOT NULL,
      currency VARCHAR(8) DEFAULT 'GHS',
      reference VARCHAR(120) UNIQUE,
      starts_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      ends_at TIMESTAMP NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
  `);
  await query(`CREATE INDEX IF NOT EXISTS idx_memberships_patient ON memberships(patient_id, status)`);
}

export async function getActiveMembership(patientId: number | null | undefined) {
  if (!patientId) return null;
  const row = await query(
    `SELECT * FROM memberships
     WHERE patient_id = $1 AND status = 'active' AND ends_at > NOW()
     ORDER BY ends_at DESC LIMIT 1`,
    [patientId]
  );
  const rec = row.rows[0];
  if (!rec) return null;
  const plan = getPlan(rec.tier);
  return { ...rec, plan };
}

export function membershipEligibilityOverlay(membership: Awaited<ReturnType<typeof getActiveMembership>>) {
  if (!membership?.plan) return null;
  const plan = membership.plan;
  return {
    source: 'membership' as const,
    eligible: true,
    consult_fee: 50,
    copay: plan.copay,
    covered_amount: Math.max(0, 50 - plan.copay),
    coverage_percent: plan.coveragePercent,
    payer_name: 'Medilynks membership',
    plan_name: `${plan.name} ${membership.period === 'yearly' ? 'yearly' : 'monthly'}`,
    policy_number: membership.reference,
    policy_id: null,
    corporate_id: null,
    member: null,
    membership_tier: plan.tier,
    dependents_allowed: plan.dependents,
    queue_priority: plan.queuePriority,
  };
}

export function registerMembershipRoutes(app: Express, authenticate: any) {
  app.get('/api/membership/plans', (_req, res) => {
    res.json({
      currency: 'GHS',
      note: 'Yearly is 10 months — two months with the house.',
      plans: MEMBERSHIP_PLANS,
    });
  });

  app.get('/api/membership/me', authenticate, async (req: AuthedRequest, res: Response) => {
    try {
      const patient = await getPatientForUser(req.user!.id);
      const current = await getActiveMembership(patient?.id);
      res.json({
        current,
        plans: MEMBERSHIP_PLANS,
        currency: 'GHS',
      });
    } catch (err) {
      console.error(err);
      res.status(500).json({ message: 'Server error' });
    }
  });

  app.post('/api/membership/initialize', authenticate, async (req: AuthedRequest, res: Response) => {
    const tier = String(req.body?.tier || '').toLowerCase() as MembershipTier;
    const period = (req.body?.period === 'yearly' ? 'yearly' : 'monthly') as MembershipPeriod;
    const plan = getPlan(tier);
    if (!plan) return res.status(400).json({ message: 'Choose Classic, Premium, Gold, or Diamond.' });

    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.status(400).json({ message: 'Complete your medical profile first.' });

      const current = await getActiveMembership(patient.id);
      if (current && current.tier === plan.tier) {
        return res.json({
          alreadyProcessed: true,
          message: `You already have ${plan.name} until ${new Date(current.ends_at).toLocaleDateString()}.`,
        });
      }

      const amountGhs = planPrice(plan, period);
      const user = await query('SELECT id, email, phone_number FROM users WHERE id = $1', [req.user!.id]);
      const checkout = await initializePaystackCheckout({
        amountGhs,
        email: paystackPaymentEmail({
          id: req.user!.id,
          email: user.rows[0]?.email || patient.email,
          phone: user.rows[0]?.phone_number || patient.phone_number,
        }),
        userId: Number(req.user!.id),
        patientId: patient.id,
        referencePrefix: 'digimem',
        metadata: {
          type: 'membership',
          tier: plan.tier,
          period,
          patient_id: patient.id,
        },
      });

      res.json({
        reference: checkout.reference,
        authorization_url: checkout.authorizationUrl,
        access_code: checkout.accessCode,
        amount: checkout.amountGhs,
        tier: plan.tier,
        period,
        demo: Boolean(checkout.demo),
        message: checkout.demo
          ? 'Paystack is not configured. Confirm this demo membership payment in the app.'
          : undefined,
      });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Could not start membership payment';
      console.error('Membership initialize error:', message);
      res.status(400).json({ message });
    }
  });

  app.post('/api/membership/activate', authenticate, async (req: AuthedRequest, res: Response) => {
    const reference = typeof req.body?.reference === 'string' ? req.body.reference.trim() : '';
    const tier = String(req.body?.tier || '').toLowerCase() as MembershipTier;
    const period = (req.body?.period === 'yearly' ? 'yearly' : 'monthly') as MembershipPeriod;
    if (!reference) return res.status(400).json({ message: 'Payment reference is required' });
    const plan = getPlan(tier);
    if (!plan) return res.status(400).json({ message: 'Choose a membership tier.' });

    try {
      const patient = await getPatientForUser(req.user!.id);
      if (!patient) return res.status(400).json({ message: 'Complete your medical profile first.' });

      const existing = await query('SELECT * FROM memberships WHERE reference = $1 LIMIT 1', [reference]);
      if (existing.rows[0]) {
        return res.json({ alreadyProcessed: true, membership: existing.rows[0] });
      }

      const expected = planPrice(plan, period);
      const verified = await resolvePaymentVerification(reference, expected);
      if (verified.currency && verified.currency !== 'GHS') {
        return res.status(400).json({ message: `Unexpected currency: ${verified.currency}` });
      }
      if (Math.abs(verified.amountGhs - expected) > 0.05) {
        return res.status(400).json({
          message: `Paid amount GHS ${verified.amountGhs} does not match ${plan.name} ${period} GHS ${expected}`,
        });
      }

      const days = period === 'yearly' ? 365 : 31;
      await query(`UPDATE memberships SET status = 'superseded' WHERE patient_id = $1 AND status = 'active'`, [
        patient.id,
      ]);
      const inserted = await query(
        `INSERT INTO memberships (patient_id, user_id, tier, period, status, amount, currency, reference, starts_at, ends_at)
         VALUES ($1,$2,$3,$4,'active',$5,'GHS',$6, NOW(), NOW() + ($7 || ' days')::interval)
         RETURNING *`,
        [patient.id, req.user!.id, plan.tier, period, expected, verified.reference, String(days)]
      );

      res.json({
        message: `${plan.name} is active.`,
        membership: { ...inserted.rows[0], plan },
      });
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Could not activate membership';
      console.error('Membership activate error:', message);
      const status = message.includes('not configured') ? 503 : 400;
      res.status(status).json({ message });
    }
  });
}
