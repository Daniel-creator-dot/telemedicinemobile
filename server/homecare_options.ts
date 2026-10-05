/** Fixed care options an admin or referring doctor can turn on. Not a settings catalog. */
export const HOME_CARE_OPTION_LABELS = [
  'Stay-in',
  'Day visit',
  'Overnight',
  'Wound care',
  'Mobility help',
  'Medication reminder',
  'Companionship',
] as const;

export const HOME_CARE_STAY_IN_LINE = 'The caregiver stays in the home.';

const CANONICAL = new Map(
  HOME_CARE_OPTION_LABELS.map((label) => [label.toLowerCase(), label])
);

const CUSTOM_OPTION_MAX = 48;

function stayInText(value: string): boolean {
  const key = value.trim().toLowerCase();
  return key === 'stay-in' || key === 'stay in';
}

/** Keeps only known labels, in catalog order. Unknown values are dropped. */
export function normalizeHomeCareOptions(raw: unknown): string[] {
  const values = Array.isArray(raw) ? raw : [];
  const picked = new Set<string>();
  for (const item of values) {
    const label = CANONICAL.get(String(item ?? '').trim().toLowerCase());
    if (label) picked.add(label);
  }
  return HOME_CARE_OPTION_LABELS.filter((label) => picked.has(label));
}

/** One optional extra label. Blank becomes null. */
export function normalizeCustomOption(raw: unknown): string | null {
  const text = String(raw ?? '')
    .trim()
    .replace(/\s+/g, ' ')
    .slice(0, CUSTOM_OPTION_MAX);
  return text || null;
}

export function homeCareShowsStayIn(options: readonly string[], custom: string | null): boolean {
  if (options.some((label) => stayInText(label))) return true;
  return custom != null && stayInText(custom);
}

/**
 * Columns an edit is allowed to write.
 * A taken or closed request only corrects the phone and the note.
 * Status and claimed_by are never in this list.
 */
export function homeCarePatchColumns(open: boolean): readonly string[] {
  if (open) {
    return ['title', 'location', 'contact_phone', 'note', 'care_options', 'custom_option'];
  }
  return ['contact_phone', 'note'];
}

/** SQL for the edit. Open rows must still be unclaimed. Taken rows do not touch the claim. */
export function homeCareUpdateStatement(open: boolean): string {
  if (open) {
    return `UPDATE home_care_requests
         SET title = $1,
             location = $2,
             contact_phone = $3,
             note = $4,
             care_options = $5,
             custom_option = $6,
             updated_at = CURRENT_TIMESTAMP
         WHERE id = $7
           AND status = 'open'
           AND claimed_by IS NULL
         RETURNING id`;
  }
  return `UPDATE home_care_requests
       SET contact_phone = $1,
           note = $2,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $3
       RETURNING id`;
}
