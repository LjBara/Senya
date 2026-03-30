import { z } from 'zod';
import type { RemediationSlot } from './remediationSlots.zod.js';

const stringOptions = z
  .array(z.union([z.string(), z.number()]))
  .min(3)
  .max(6)
  .transform((arr) => arr.map((x) => String(x).trim()))
  .refine((arr) => arr.every((s) => s.length > 0), 'empty option')
  .refine((arr) => new Set(arr).size === arr.length, 'options must be distinct');

const intCoerce = z.preprocess((v) => {
  if (typeof v === 'number' && Number.isFinite(v)) return Math.trunc(v);
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number.parseInt(v.trim(), 10);
    return Number.isFinite(n) ? n : v;
  }
  return v;
}, z.number().int());

/** Gemini often omits explanation; avoid failing the whole batch. */
const explanationLoose = z
  .union([z.string(), z.number(), z.boolean()])
  .optional()
  .transform((v) => (v === undefined || v === null ? '' : String(v)));

const questionCoerce = z
  .union([z.string(), z.number(), z.boolean()])
  .transform((v) => String(v).trim())
  .pipe(z.string().min(1));

const mcLike = z.object({
  type: z.enum(['multiple_choice', 'circle_answer']),
  id: z.number().int().optional(),
  question: questionCoerce,
  options: stringOptions,
  correctAnswer: intCoerce,
  explanation: explanationLoose,
  objects: z.array(z.string()).optional(),
  objectCount: z.number().int().optional(),
});

const fillLike = z.object({
  type: z.enum(['fill_blank', 'write_number']),
  id: z.number().int().optional(),
  question: z.string().min(1),
  correctAnswer: z.union([z.string(), z.number(), z.boolean()]).transform((v) => String(v).trim()),
  explanation: explanationLoose,
});

const trueFalse = z.object({
  type: z.literal('true_false'),
  id: z.number().int().optional(),
  question: z.string().min(1),
  correctAnswer: z.preprocess(
    (v) => (v === 'true' ? true : v === 'false' ? false : v),
    z.boolean()
  ),
  explanation: explanationLoose,
});

const stringOrNumArray = z
  .array(z.union([z.string(), z.number()]))
  .transform((a) => a.map((x) => String(x).trim()));

const matching = z.object({
  type: z.literal('matching'),
  id: z.number().int().optional(),
  question: z.string().min(1),
  leftItems: stringOrNumArray.pipe(z.array(z.string()).min(1)),
  rightItems: stringOrNumArray.pipe(z.array(z.string()).min(1)),
  correctMatches: z.array(z.coerce.number().int()),
  explanation: explanationLoose,
});

const dragDrop = z.object({
  type: z.literal('drag_drop'),
  id: z.number().int().optional(),
  question: z.string().min(1),
  sequence: stringOrNumArray,
  availableNumbers: stringOrNumArray,
  correctAnswer: stringOrNumArray,
  blankPositions: z.array(z.coerce.number().int()),
  explanation: explanationLoose,
});

function refineMcLike(data: z.infer<typeof mcLike>): boolean {
  const { correctAnswer, options } = data;
  return correctAnswer >= 0 && correctAnswer < options.length;
}

function refineMatching(data: z.infer<typeof matching>): boolean {
  const n = data.leftItems.length;
  if (data.rightItems.length !== n) return false;
  if (data.correctMatches.length !== n) return false;
  return data.correctMatches.every((m) => m >= 0 && m < n);
}

function refineDragDrop(data: z.infer<typeof dragDrop>): boolean {
  if (data.blankPositions.length !== data.correctAnswer.length) return false;
  for (let i = 0; i < data.blankPositions.length; i++) {
    const pos = data.blankPositions[i];
    if (pos < 0 || pos >= data.sequence.length) return false;
  }
  return true;
}

const mcLikeRefined = mcLike.refine(refineMcLike, 'correctAnswer out of range');
const matchingRefined = matching.refine(refineMatching, 'matching shape invalid');
const dragDropRefined = dragDrop.refine(refineDragDrop, 'drag_drop shape invalid');

function typesCompatible(slot: RemediationSlot, rawType: unknown): boolean {
  if (rawType === slot.type) return true;
  if (
    (slot.type === 'multiple_choice' || slot.type === 'circle_answer') &&
    (rawType === 'multiple_choice' || rawType === 'circle_answer')
  ) {
    return true;
  }
  return false;
}

/** Gemini JSON often uses { text } options or a JSON string array. */
function normalizeMcOptionsRaw(raw: unknown): unknown[] | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw === 'string') {
    const t = raw.trim();
    if (t.startsWith('[')) {
      try {
        return normalizeMcOptionsRaw(JSON.parse(t) as unknown);
      } catch {
        return null;
      }
    }
    return null;
  }
  if (!Array.isArray(raw)) return null;
  return raw.map((item) => {
    if (item === null || item === undefined) return '';
    if (typeof item === 'string' || typeof item === 'number' || typeof item === 'boolean') {
      return item;
    }
    if (typeof item === 'object') {
      const r = item as Record<string, unknown>;
      const v = r.text ?? r.label ?? r.value ?? r.option ?? r.title ?? r.content;
      if (v !== undefined && v !== null) return String(v);
    }
    return String(item);
  });
}

/** Map common Generative AI field names to our schema before parsing. */
function applyGenerativeMcAliases(o: Record<string, unknown>): Record<string, unknown> {
  const x = { ...o };
  if (x.options === undefined && Array.isArray(x.choices)) {
    x.options = x.choices;
  }
  const q = x.question;
  if (q === undefined || q === null || (typeof q === 'string' && q.trim() === '')) {
    const alt = x.stem ?? x.prompt ?? x.text ?? x.body;
    if (alt !== undefined && alt !== null && String(alt).trim() !== '') {
      x.question = String(alt);
    }
  }
  if (x.correctAnswer === undefined || x.correctAnswer === null) {
    if (x.correctIndex !== undefined && x.correctIndex !== null) {
      x.correctAnswer = x.correctIndex;
    } else if (x.answer !== undefined && x.answer !== null) {
      x.correctAnswer = x.answer;
    }
  }
  return x;
}

function tryParseMcLikeForSlot(
  o: Record<string, unknown>,
  slotType: 'multiple_choice' | 'circle_answer',
  index: number
): Record<string, unknown> | null {
  const aliased = applyGenerativeMcAliases(o);
  const normOpts = normalizeMcOptionsRaw(aliased.options);
  if (!normOpts) return null;
  const base = { ...aliased, type: slotType, options: normOpts };

  const candidates: Record<string, unknown>[] = [base];

  const ca0 = aliased.correctAnswer;
  const opts = normOpts;
  if (typeof ca0 === 'string' && ca0.trim() !== '') {
    const idx = opts.findIndex((x) => String(x).trim() === String(ca0).trim());
    if (idx >= 0) {
      candidates.unshift({ ...base, correctAnswer: idx });
    }
  }

  if (typeof ca0 === 'number' && Number.isFinite(ca0)) {
    const n = Math.trunc(ca0);
    if (n >= 1 && n <= opts.length) {
      candidates.push({ ...base, correctAnswer: n - 1 });
    }
  }

  for (const cand of candidates) {
    const r = mcLikeRefined.safeParse(cand);
    if (r.success) {
      return { ...r.data, id: index + 1, type: slotType };
    }
  }
  return null;
}

/** For debug logs: first slot where parsing fails (strict batch or merge diagnostics). */
export function inspectFirstUnparsedSlot(
  slots: RemediationSlot[],
  questionsRaw: unknown
): { index: number; expectedType: string; rawKeys: string[] } | null {
  if (questionsRaw === null || typeof questionsRaw !== 'object') return null;
  const arr = (questionsRaw as Record<string, unknown>).questions;
  if (!Array.isArray(arr)) {
    return { index: -1, expectedType: 'questions is not an array', rawKeys: [] };
  }
  if (arr.length !== slots.length) {
    return {
      index: -1,
      expectedType: `length mismatch: model ${arr.length} vs slots ${slots.length}`,
      rawKeys: [],
    };
  }
  for (let i = 0; i < slots.length; i++) {
    const rawItem = arr[i];
    const q = parseQuestionForSlot(slots[i], rawItem, i);
    if (!q) {
      const keys =
        rawItem !== null && typeof rawItem === 'object'
          ? Object.keys(rawItem as object)
          : [];
      return { index: i, expectedType: slots[i].type, rawKeys: keys };
    }
  }
  return null;
}

export function parseQuestionForSlot(
  slot: RemediationSlot,
  raw: unknown,
  index: number
): Record<string, unknown> | null {
  try {
    if (raw === null || typeof raw !== 'object') return null;
    const o = raw as Record<string, unknown>;
    const declared = o.type;
    const effectiveType =
      declared === undefined || declared === null ? slot.type : declared;
    if (!typesCompatible(slot, effectiveType)) return null;

    let parsed: Record<string, unknown>;

    switch (slot.type) {
      case 'multiple_choice':
      case 'circle_answer': {
        const mc = tryParseMcLikeForSlot(o, slot.type, index);
        if (!mc) return null;
        parsed = mc;
        break;
      }
      case 'fill_blank':
      case 'write_number': {
        const r = fillLike.parse({ ...o, type: slot.type });
        parsed = { ...r, id: index + 1, type: slot.type };
        break;
      }
      case 'true_false': {
        const r = trueFalse.parse(o);
        parsed = { ...r, id: index + 1 };
        break;
      }
      case 'matching': {
        const r = matchingRefined.parse(o);
        parsed = { ...r, id: index + 1 };
        break;
      }
      case 'drag_drop': {
        const r = dragDropRefined.parse(o);
        parsed = { ...r, id: index + 1 };
        break;
      }
      default:
        return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

export function validateOrderedQuestions(
  slots: RemediationSlot[],
  questionsRaw: unknown
): Record<string, unknown>[] | null {
  if (questionsRaw === null || typeof questionsRaw !== 'object') return null;
  const arr = (questionsRaw as Record<string, unknown>).questions;
  if (!Array.isArray(arr) || arr.length !== slots.length) {
    return null;
  }

  const out: Record<string, unknown>[] = [];
  for (let i = 0; i < slots.length; i++) {
    const q = parseQuestionForSlot(slots[i], arr[i], i);
    if (!q) {
      return null;
    }
    out.push(q);
  }
  return out;
}

/**
 * Slot-by-slot validation: use AI item when it parses; otherwise clone original for that slot.
 * Lets a partially valid model response through instead of discarding the whole batch.
 */
export function mergeRemediationWithFallback(
  slots: RemediationSlot[],
  questionsRaw: unknown,
  originals: Record<string, unknown>[]
): { questions: Record<string, unknown>[]; aiFilledCount: number } | null {
  if (originals.length !== slots.length) return null;

  const arr =
    questionsRaw !== null &&
    typeof questionsRaw === 'object' &&
    Array.isArray((questionsRaw as Record<string, unknown>).questions)
      ? ((questionsRaw as Record<string, unknown>).questions as unknown[])
      : [];

  const out: Record<string, unknown>[] = [];
  let aiFilledCount = 0;

  for (let i = 0; i < slots.length; i++) {
    const rawItem = arr[i];
    const parsed =
      rawItem !== undefined && rawItem !== null
        ? parseQuestionForSlot(slots[i], rawItem, i)
        : null;
    if (parsed) {
      aiFilledCount++;
      out.push(parsed);
    } else {
      const fb = JSON.parse(JSON.stringify(originals[i])) as Record<string, unknown>;
      fb.id = i + 1;
      out.push(fb);
    }
  }

  return { questions: out, aiFilledCount };
}
