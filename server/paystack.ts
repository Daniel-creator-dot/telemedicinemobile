import axios from 'axios';
import { randomBytes } from 'crypto';
import { query } from './db';

export async function getSetting(key: string): Promise<string> {
  const row = await query('SELECT value FROM settings WHERE key = $1 LIMIT 1', [key]);
  return String(row.rows[0]?.value || '').trim();
}

export async function getPaystackPublicKey(): Promise<string> {
  const fromDb = await getSetting('paystack_public_key');
  if (fromDb) return fromDb;
  return process.env.PAYSTACK_PUBLIC_KEY?.trim() || '';
}

export async function getPaystackSecretKey(): Promise<string> {
  const fromDb = await getSetting('paystack_secret_key');
  if (fromDb) return fromDb;
  return process.env.PAYSTACK_SECRET_KEY?.trim() || '';
}

export function paystackKeysMatch(publicKey: string, secretKey: string): boolean {
  const pubTest = publicKey.startsWith('pk_test_');
  const pubLive = publicKey.startsWith('pk_live_');
  const secTest = secretKey.startsWith('sk_test_');
  const secLive = secretKey.startsWith('sk_live_');
  if (pubTest && secTest) return true;
  if (pubLive && secLive) return true;
  return !pubTest && !pubLive && !secTest && !secLive;
}

export function paystackPaymentEmail(user: { id: number | string; email?: string | null; phone?: string | null }) {
  const email = user.email?.trim();
  if (email && email.includes('@')) return email;
  const digits = (user.phone || '').replace(/\D/g, '');
  if (digits.length >= 9) return `patient${digits}@digihealth.app`;
  return `patient${String(user.id).replace(/\D/g, '').slice(0, 12)}@digihealth.app`;
}

export function isDemoPaymentReference(reference: string) {
  return /^digidemo_/i.test(String(reference || '').trim());
}

/** Demo confirmations are allowed only when no Paystack secret is configured. */
export async function isDemoPayEnabled() {
  return !(await isPaystackConfigured());
}

export async function verifyPaystackTransaction(reference: string) {
  const secretKey = await getPaystackSecretKey();
  if (!secretKey) {
    throw new Error('Paystack secret key is not configured. Add sk_test_ or sk_live_ in Admin or PAYSTACK_SECRET_KEY.');
  }
  const publicKey = await getPaystackPublicKey();
  if (publicKey && !paystackKeysMatch(publicKey, secretKey)) {
    throw new Error('Paystack public and secret keys must both be test or both be live (pk_test_ with sk_test_, etc.)');
  }

  try {
    const response = await axios.get(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      { headers: { Authorization: `Bearer ${secretKey}` } }
    );
    if (!response.data?.status) {
      throw new Error(response.data?.message || 'Paystack could not verify this payment');
    }
    const data = response.data.data;
    if (data.status !== 'success') {
      throw new Error(`Payment was not successful (status: ${data.status})`);
    }
    return {
      amountGhs: Number(data.amount) / 100,
      currency: data.currency as string,
      reference: data.reference as string,
      gateway: 'paystack' as const,
    };
  } catch (err: unknown) {
    if (axios.isAxiosError(err) && err.response?.data?.message) {
      throw new Error(String(err.response.data.message));
    }
    throw err;
  }
}

/**
 * Verify a live Paystack charge, or accept a digidemo_ reference when keys are missing.
 * Pass expectedAmountGhs so demo confirms match the copay / plan price.
 */
export async function resolvePaymentVerification(reference: string, expectedAmountGhs: number) {
  const ref = String(reference || '').trim();
  if (!ref) throw new Error('Payment reference is required');

  if (isDemoPaymentReference(ref)) {
    if (!(await isDemoPayEnabled())) {
      throw new Error('Demo payments are disabled while Paystack keys are configured.');
    }
    if (!Number.isFinite(expectedAmountGhs) || expectedAmountGhs < 1) {
      throw new Error('Invalid demo payment amount');
    }
    return {
      amountGhs: expectedAmountGhs,
      currency: 'GHS',
      reference: ref,
      gateway: 'demo' as const,
    };
  }

  return verifyPaystackTransaction(ref);
}

export async function initializePaystackCheckout(opts: {
  amountGhs: number;
  email: string;
  userId: number;
  appointmentId?: number | null;
  patientId?: number | null;
  metadata?: Record<string, unknown>;
  referencePrefix?: string;
}) {
  const amount = Math.round(opts.amountGhs * 100);
  if (!Number.isFinite(amount) || amount < 100) {
    throw new Error('Minimum charge is GHS 1');
  }

  // No secret key → offline demo checkout (does not invent Paystack credentials).
  if (!(await isPaystackConfigured())) {
    const reference = `digidemo_${Date.now()}_${randomBytes(4).toString('hex')}`;
    return {
      reference,
      authorizationUrl: '',
      accessCode: undefined,
      amountGhs: opts.amountGhs,
      demo: true as const,
    };
  }

  const secretKey = await getPaystackSecretKey();
  const publicKey = await getPaystackPublicKey();
  if (publicKey && !paystackKeysMatch(publicKey, secretKey)) {
    throw new Error('Paystack public and secret keys must both be test or both be live.');
  }

  const prefix = opts.referencePrefix?.replace(/[^a-z0-9_]/gi, '') || 'digihealth';
  const reference = `${prefix}_${Date.now()}_${randomBytes(4).toString('hex')}`;
  const callbackBase =
    process.env.PAYSTACK_CALLBACK_URL?.trim() ||
    process.env.APP_URL?.trim() ||
    '';
  if (!callbackBase) {
    throw new Error(
      'Paystack callback URL is not configured. Set PAYSTACK_CALLBACK_URL or APP_URL to your public API origin.'
    );
  }
  if (/localhost|127\.0\.0\.1/i.test(callbackBase) && process.env.NODE_ENV === 'production') {
    throw new Error(
      'Paystack callback cannot use localhost in production. Set PAYSTACK_CALLBACK_URL or APP_URL.'
    );
  }
  const callbackUrl = `${callbackBase.replace(/\/$/, '')}/api/paystack/callback`;

  const response = await axios.post(
    'https://api.paystack.co/transaction/initialize',
    {
      email: opts.email,
      amount,
      currency: 'GHS',
      reference,
      callback_url: callbackUrl,
      channels: ['card', 'mobile_money', 'bank'],
      metadata: {
        type: 'visit_copay',
        appointment_id: opts.appointmentId ?? null,
        patient_id: opts.patientId || null,
        user_id: opts.userId,
        ...(opts.metadata || {}),
      },
    },
    { headers: { Authorization: `Bearer ${secretKey}` } }
  );

  if (!response.data?.status) {
    throw new Error(response.data?.message || 'Could not start Paystack checkout');
  }
  const data = response.data.data;
  if (!data?.authorization_url || !data?.reference) {
    throw new Error('Paystack did not return a checkout URL');
  }

  return {
    reference: data.reference as string,
    authorizationUrl: data.authorization_url as string,
    accessCode: data.access_code as string | undefined,
    amountGhs: opts.amountGhs,
    demo: false as const,
  };
}

export async function isPaystackConfigured() {
  const secret = await getPaystackSecretKey();
  return Boolean(secret);
}
