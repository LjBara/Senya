import db from '../db/connection.js';
import {
  clientLessonSeedTitle,
  resolveClientLessonIdToDb,
} from '../config/lessonAliases.js';

/** Optional client payload when DB has no matching lesson row (e.g. empty `lessons` table). */
export type ClientLessonHint = {
  lessonTitle?: string;
  subtopics?: string[];
};

export type ResolvedLesson = {
  id: string;
  title: string;
  description: string | null;
  category: string;
  subtopicTitles: string[];
};

function rowToLesson(lessonRow: Record<string, unknown>, subtopics: { title: string }[]): ResolvedLesson {
  return {
    id: String(lessonRow.id),
    title: String(lessonRow.title ?? ''),
    description: lessonRow.description != null ? String(lessonRow.description) : null,
    category: String(lessonRow.category ?? ''),
    subtopicTitles: subtopics.map((s) => s.title),
  };
}

/**
 * Resolution: direct DB id → client alias → seed title → synthetic row for known client ids (empty DB).
 * On missing schema or any SQLite error, returns null so callers use client-only lessonContext (plan: no hard-fail).
 */
export function resolveLessonRecord(
  lessonId: string,
  clientHint?: ClientLessonHint | null
): ResolvedLesson | null {
  const trimmed = lessonId.trim();
  if (!trimmed) return null;

  try {
    const viaAlias = resolveClientLessonIdToDb(trimmed);
    const tryIds = viaAlias === trimmed ? [trimmed] : [trimmed, viaAlias];

    for (const id of tryIds) {
      const lessonRow = db.prepare('SELECT * FROM lessons WHERE id = ?').get(id) as Record<string, unknown> | null;
      if (lessonRow) {
        const subtopics = db
          .prepare('SELECT title FROM subtopics WHERE lesson_id = ? ORDER BY order_num')
          .all(id) as { title: string }[];
        return rowToLesson(lessonRow, subtopics);
      }
    }

    const byTitle = db.prepare('SELECT * FROM lessons WHERE title = ?').get(trimmed) as Record<string, unknown> | null;
    if (byTitle) {
      const id = String(byTitle.id);
      const subtopics = db
        .prepare('SELECT title FROM subtopics WHERE lesson_id = ? ORDER BY order_num')
        .all(id) as { title: string }[];
      return rowToLesson(byTitle, subtopics);
    }

    const seedTitle = clientLessonSeedTitle(trimmed);
    if (seedTitle) {
      const bySeedTitle = db
        .prepare('SELECT * FROM lessons WHERE title = ?')
        .get(seedTitle) as Record<string, unknown> | null;
      if (bySeedTitle) {
        const id = String(bySeedTitle.id);
        const subtopics = db
          .prepare('SELECT title FROM subtopics WHERE lesson_id = ? ORDER BY order_num')
          .all(id) as { title: string }[];
        return rowToLesson(bySeedTitle, subtopics);
      }
      const subFromClient =
        clientHint?.subtopics?.filter((s) => typeof s === 'string' && s.trim() !== '') ?? [];
      const title = clientHint?.lessonTitle?.trim() || seedTitle;
      return {
        id: resolveClientLessonIdToDb(trimmed),
        title,
        description: null,
        category: '',
        subtopicTitles: subFromClient,
      };
    }
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.warn('[lessonResolve] resolveLessonRecord: DB unavailable or schema missing; using client context only.', msg);
    // #region agent log
    fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'post-fix',hypothesisId:'H-resolve-skip',location:'lessonResolve.service.ts:catch',message:'lesson DB lookup skipped',data:{errMsg:msg.slice(0,200)},timestamp:Date.now()})}).catch(()=>{});
    // #endregion
  }

  return null;
}

export type LessonContext = {
  topicId?: string;
  topicTitle?: string;
  lessonTitle?: string;
  /** Client-side subtopic titles (merged with DB for prompts). */
  subtopics?: string[];
  gradeLevel?: string;
  locale?: string;
  constraints?: string[];
  vocabulary?: string[];
  /** Extra lines from client (e.g. legacy string context split by newline) */
  notes?: string[];
};

export function mergeLessonContext(
  resolved: ResolvedLesson | null,
  client: LessonContext | null | undefined
): LessonContext & {
  subtopicsFromDb: string[];
  subtopicsForPrompt: string[];
  resolvedLessonId: string | null;
} {
  const c = client ?? {};
  const subtopicsFromDb = resolved?.subtopicTitles ?? [];
  const fromClient = c.subtopics ?? [];
  const subtopicsForPrompt = [...new Set([...subtopicsFromDb, ...fromClient])];
  const lessonTitle = c.lessonTitle?.trim() || resolved?.title || '';

  return {
    ...c,
    lessonTitle,
    subtopicsFromDb,
    subtopicsForPrompt,
    resolvedLessonId: resolved?.id ?? null,
    notes: c.notes?.length ? c.notes : undefined,
  };
}

export function lessonContextToPromptBlock(ctx: ReturnType<typeof mergeLessonContext>): string {
  const lines: string[] = [];
  lines.push(`Lesson title: ${ctx.lessonTitle || '(not specified)'}`);
  if (ctx.topicTitle) lines.push(`Topic: ${ctx.topicTitle}`);
  if (ctx.topicId) lines.push(`Topic id: ${ctx.topicId}`);
  if (ctx.gradeLevel) lines.push(`Grade: ${ctx.gradeLevel}`);
  if (ctx.locale) lines.push(`Locale: ${ctx.locale}`);
  if (ctx.subtopicsForPrompt.length) {
    lines.push(`Subtopics (curriculum): ${ctx.subtopicsForPrompt.join(', ')}`);
  }
  if (ctx.constraints?.length) lines.push(`Constraints: ${ctx.constraints.join('; ')}`);
  if (ctx.vocabulary?.length) lines.push(`Vocabulary: ${ctx.vocabulary.join(', ')}`);
  if (ctx.notes?.length) lines.push(`Additional notes:\n${ctx.notes.join('\n')}`);
  return lines.join('\n');
}
