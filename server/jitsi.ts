import crypto from 'crypto';

/**
 * Medilynks video rooms.
 *
 * meet.jit.si / 8x8.vc require an authenticated moderator before a conference
 * can start. jitsi.debian.social now forces SSO (salsa.debian.org OAuth) via
 * tokenAuthUrl — anonymous embeds hang on "Asking to join meeting...".
 * Use a community instance where the first joiner is moderator with no login.
 * Override with JITSI_DOMAIN if you self-host.
 */
export const JITSI_DOMAIN = (process.env.JITSI_DOMAIN || 'jitsi.member.fsf.org').replace(
  /^https?:\/\//,
  '',
).replace(/\/$/, '');

const LOCKED_HOSTS = new Set([
  'meet.jit.si',
  '8x8.vc',
  'jaas.8x8.vc',
  // Debian community instance now requires SSO to become moderator.
  'jitsi.debian.social',
]);

/** Unguessable public Jitsi room. Never use sequential or short alphabetic names. */
export function createSecureJitsiLink() {
  const room = `medilynks-${crypto.randomBytes(18).toString('hex')}`;
  return `https://${JITSI_DOMAIN}/${room}`;
}

/** Rewrite locked-host links so both parties land on the same Medilynks host. */
export function normalizeJitsiMeetingLink(link: string | null | undefined): string | null {
  if (!link || !String(link).trim()) return null;
  const trimmed = String(link).trim();
  try {
    const withScheme = trimmed.includes('://') ? trimmed : `https://${trimmed}`;
    const uri = new URL(withScheme);
    const segs = uri.pathname.split('/').filter(Boolean);
    const room = segs.join('/') || trimmed.replace(/[^a-zA-Z0-9._-]/g, '');
    const host = LOCKED_HOSTS.has(uri.hostname.toLowerCase()) ? JITSI_DOMAIN : uri.hostname;
    return `https://${host}/${room}`;
  } catch {
    return `https://${JITSI_DOMAIN}/${trimmed.replace(/[^a-zA-Z0-9._-]/g, '')}`;
  }
}
