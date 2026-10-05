import type { Request, Response } from 'express';

/**
 * Approximate cedis per US dollar, used only to display prices to visitors
 * outside Ghana. This is not a live foreign-exchange feed. Update the number
 * when the cedi moves. Paystack for this merchant still charges the original
 * GHS amount (see PAYSTACK_CHARGE_CURRENCY).
 */
export const GHS_PER_USD = 15.5;

/**
 * This Paystack integration charges Ghana cedis. The merchant uses Ghana
 * cards and Mobile Money, and initialize always sends currency GHS.
 * Sending USD would fail on an account that is not enabled for it, and a
 * failed call must not be treated as a successful dollar charge.
 * Visitors outside Ghana see USD converted from the same GHS prices.
 */
export const PAYSTACK_CHARGE_CURRENCY = 'GHS' as const;

export type DisplayCurrency = 'GHS' | 'USD';

/** Cloudflare uses XX for unknown and T1 for Tor. Those stay on the GHS default. */
const UNKNOWN_COUNTRY = new Set(['XX', 'T1']);

const MONEY_FIELDS = new Set([
  'copay',
  'consult_fee',
  'covered_amount',
  'amount',
  'copay_amount',
  'consultation_fee',
  'annual_limit',
  'spent_ytd',
  'limit_remaining',
  'monthlyGhs',
  'yearlyGhs',
  'approved_amount',
  'requested_amount',
]);

/**
 * Country from Cloudflare's CF-IPCountry header only.
 * The address itself is never read, stored, or logged.
 * Missing or unknown country returns null so callers keep GHS.
 */
export function countryFromRequest(req: Request): string | null {
  const raw = req.get('CF-IPCountry');
  if (!raw) return null;
  const code = raw.trim().toUpperCase();
  if (!/^[A-Z]{2}$/.test(code) || UNKNOWN_COUNTRY.has(code)) return null;
  return code;
}

export function currencyForCountry(country: string | null): DisplayCurrency {
  if (!country || country === 'GH') return 'GHS';
  return 'USD';
}

export function currencyForRequest(req: Request): DisplayCurrency {
  return currencyForCountry(countryFromRequest(req));
}

export function displayAmountFromGhs(amountGhs: number, currency: DisplayCurrency): number {
  if (!Number.isFinite(amountGhs)) return 0;
  if (currency === 'GHS') return Math.round(amountGhs * 100) / 100;
  return Math.round((amountGhs / GHS_PER_USD) * 100) / 100;
}

export function formatMoneyFromGhs(amountGhs: number, currency: DisplayCurrency): string {
  if (currency === 'USD') {
    return `$${displayAmountFromGhs(amountGhs, 'USD').toFixed(2)}`;
  }
  const n = displayAmountFromGhs(amountGhs, 'GHS');
  const text = Number.isInteger(n) ? n.toFixed(0) : n.toFixed(2);
  return `GHS ${text}`;
}

export function rewriteGhsCopy(text: string, currency: DisplayCurrency): string {
  return text.replace(/GHS\s+(\d+(?:\.\d+)?)/g, (_all, raw) => formatMoneyFromGhs(Number(raw), currency));
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  if (!value || typeof value !== 'object') return false;
  if (value instanceof Date) return false;
  if (Array.isArray(value)) return false;
  const proto = Object.getPrototypeOf(value);
  return proto === Object.prototype || proto === null;
}

/** Add display labels. Numeric fee fields stay in GHS so charges are unchanged. */
export function decorateMoney(value: unknown, currency: DisplayCurrency): unknown {
  if (Array.isArray(value)) return value.map((item) => decorateMoney(item, currency));
  if (!isPlainObject(value)) return value;
  const next: Record<string, unknown> = {
    ...value,
    currency,
    charge_currency: PAYSTACK_CHARGE_CURRENCY,
  };
  for (const [key, field] of Object.entries(value)) {
    if (Array.isArray(field) || isPlainObject(field)) {
      next[key] = decorateMoney(field, currency);
      continue;
    }
    if (!MONEY_FIELDS.has(key) || field == null || field === '') continue;
    const amount = Number(field);
    if (!Number.isFinite(amount)) continue;
    next[`${key}_label`] = formatMoneyFromGhs(amount, currency);
    next[`${key}_display`] = displayAmountFromGhs(amount, currency);
  }
  return next;
}

export function localePayload(req: Request) {
  const country = countryFromRequest(req);
  const currency = currencyForCountry(country);
  return {
    country,
    currency,
    charge_currency: PAYSTACK_CHARGE_CURRENCY,
    ghs_per_usd: GHS_PER_USD,
    paystack_charges: PAYSTACK_CHARGE_CURRENCY,
  };
}

export function sendCurrencyJson(res: Response, req: Request, body: unknown) {
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('Vary', 'CF-IPCountry');
  res.json(decorateMoney(body, currencyForRequest(req)));
}
