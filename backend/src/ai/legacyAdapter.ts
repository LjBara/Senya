import type { ClientLessonContext, RemediationSlot } from './remediationSlots.zod.js';

const KNOWN_SLOT_TYPES = new Set<RemediationSlot['type']>([
  'multiple_choice',
  'circle_answer',
  'fill_blank',
  'write_number',
  'true_false',
  'matching',
  'drag_drop',
]);

function mapQuestionType(t: unknown): RemediationSlot['type'] {
  if (typeof t !== 'string') return 'multiple_choice';
  return KNOWN_SLOT_TYPES.has(t as RemediationSlot['type'])
    ? (t as RemediationSlot['type'])
    : 'multiple_choice';
}

function summaryFromIncorrect(q: Record<string, unknown>): string {
  const parts: string[] = [];
  if (typeof q.question === 'string') parts.push(q.question);
  if (typeof q.objectCount === 'number' && Number.isFinite(q.objectCount)) {
    parts.push(`(visual count ~${q.objectCount})`);
  }
  const s = parts.join(' ').trim();
  return s.length > 500 ? s.slice(0, 500) : s || '(no summary)';
}

/**
 * Builds slim slots + optional structured context from legacy POST /generate-quiz body.
 */
export function legacyIncorrectToSlots(incorrectQuestions: unknown[]): RemediationSlot[] {
  const arr = Array.isArray(incorrectQuestions) ? incorrectQuestions : [];
  return arr
    .filter((x) => x !== null && typeof x === 'object')
    .map((x) => {
      const q = x as Record<string, unknown>;
      return {
        type: mapQuestionType(q.type),
        summary: summaryFromIncorrect(q),
      } satisfies RemediationSlot;
    });
}

export function legacyStringToLessonContext(lessonContext: string): ClientLessonContext {
  const lines = lessonContext.split('\n').map((l) => l.trim()).filter(Boolean);
  const first = lines[0] ?? '';
  const lessonTitle = first.replace(/^Lesson:\s*/i, '').trim() || undefined;
  const notes = lines.length > 1 ? lines.slice(1) : undefined;
  return {
    lessonTitle,
    notes,
  };
}
