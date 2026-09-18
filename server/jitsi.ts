import crypto from 'crypto';

/**
 * Medilynks video rooms.
 *
 * Locked public hosts (anonymous embeds cannot start a conference):
 * - meet.jit.si / 8x8.vc — authenticated moderator required
 * - jitsi.debian.social — tokenAuthUrl → salsa.debian.org SSO
 * - jitsi.member.fsf.org — FSF associate-member login to start rooms
 *
 * Default host: meet.ffmuc.net (no tokenAuthUrl; first joiner is moderator).
 * That host blocks iframes (CSP/XFO) — the Flutter client loads rooms as a
 * top-level WebView document. Override with JITSI_DOMAIN if you self-host.
 */
export const JITSI_DOMAIN = (process.env.JITSI_DOMAIN || 'meet.ffmuc.net').replace(
  /^https?:\/\//,
  '',
).replace(/\/$/, '');

const LOCKED_HOSTS = new Set([
  'meet.jit.si',
  '8x8.vc',
  'jaas.8x8.vc',
  'jitsi.debian.social',
  'jitsi.member.fsf.org',
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
