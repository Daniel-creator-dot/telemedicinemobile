import crypto from 'crypto';

/**
 * Healynks video rooms.
 *
 * Host choice (checked 2026-10-05):
 * - meet.jit.si — free, but anonymous room creation is rejected. config.js
 *   sets tokenAuthUrl to a Google/GitHub/Facebook sign-in, and a new room
 *   stops on "Waiting for a moderator… Log-in". That would send a doctor
 *   or patient to a third-party account. 8x8.vc / JaaS need an API secret.
 * - meet.ffmuc.net — anonymous, but X-Frame-Options SAMEORIGIN plus a tight
 *   frame-ancestors policy blank the in-page embed, and the instance is
 *   often slow or blocked inside mobile WebViews.
 * - meet.evolix.org — free public Jitsi Meet run by Evolix. No API key, no
 *   login, first joiner is moderator, and the room can be embedded
 *   (no X-Frame-Options / frame-ancestors). external_api.js is served over
 *   HTTPS and fires videoConferenceJoined for an anonymous room.
 *
 * The room name is what we keep. The URL is always rebuilt from that name
 * plus JITSI_DOMAIN so a stored meet.ffmuc.net / meet.jit.si link joins the
 * same healynks- room on the current host. Override JITSI_DOMAIN only if
 * you self-host; the Flutter default must match.
 */
export const JITSI_DOMAIN = (process.env.JITSI_DOMAIN || 'meet.evolix.org')
  .replace(/^https?:\/\//, '')
  .replace(/\/$/, '');

/** Unguessable public Jitsi room. Never use sequential or short alphabetic names. */
export function createSecureJitsiLink() {
  const room = `healynks-${crypto.randomBytes(18).toString('hex')}`;
  return meetingUrlForRoom(room);
}

export function jitsiRoomNameFromLink(link: string): string {
  const trimmed = String(link).trim();
  try {
    const withScheme = trimmed.includes('://') ? trimmed : `https://${trimmed}`;
    const uri = new URL(withScheme);
    const segs = uri.pathname.split('/').filter(Boolean);
    if (segs.length) return segs.join('/');
  } catch {
    // Fall through to a sanitized token.
  }
  return trimmed.replace(/[^a-zA-Z0-9._-]/g, '');
}

/** https URL on the current host. One constant controls every join. */
export function meetingUrlForRoom(room: string): string {
  const clean = String(room).replace(/[^a-zA-Z0-9._/-]/g, '').replace(/^\/+/, '');
  return `https://${JITSI_DOMAIN}/${clean}`;
}

/**
 * Rebuild a stored meeting link onto the current host, keeping the room name.
 * Safe for calls that have not started: both clients read the same name and
 * land on the same URL. The room id is not rotated, so an old bookmark still
 * names the same healynks- room.
 */
export function normalizeJitsiMeetingLink(link: string | null | undefined): string | null {
  if (!link || !String(link).trim()) return null;
  const room = jitsiRoomNameFromLink(String(link));
  if (!room) return null;
  return meetingUrlForRoom(room);
}
