import crypto from 'crypto';

/** Unguessable public Jitsi room. Never use sequential or short alphabetic names. */
export function createSecureJitsiLink() {
  const room = `digihealth-${crypto.randomBytes(18).toString('hex')}`;
  return `https://meet.jit.si/${room}`;
}
