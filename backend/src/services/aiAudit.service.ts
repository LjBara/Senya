import db from '../db/connection.js';
import type { RemediationSlot } from '../ai/remediationSlots.zod.js';

export function ensureGeneratedQuizzesTable(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS generated_quizzes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lesson_id TEXT,
      questions_json TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);
}

/** Compliance / debug audit trail (additive migration for existing DBs). */
export function ensureAiQuestionGenerationsTable(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS ai_question_generations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_id TEXT NOT NULL,
      kind TEXT,
      lesson_id_input TEXT,
      lesson_id_resolved TEXT,
      model TEXT,
      fallback INTEGER NOT NULL DEFAULT 0,
      slot_count INTEGER,
      input_json TEXT,
      output_json TEXT,
      error_text TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);
}

export function sanitizeSlotsForAudit(slots: RemediationSlot[]): string {
  return JSON.stringify({
    count: slots.length,
    types: slots.map((s) => s.type),
    summaries: slots.map((s) => s.summary.slice(0, 200)),
  });
}

export function persistGeneratedQuizLegacy(lessonId: string, questions: unknown[]): void {
  try {
    ensureGeneratedQuizzesTable();
    db.prepare(`INSERT INTO generated_quizzes (lesson_id, questions_json) VALUES (?, ?)`).run(
      lessonId,
      JSON.stringify(questions)
    );
  } catch (e) {
    console.error('persistGeneratedQuizLegacy failed:', e);
  }
}

export function persistAiQuestionGeneration(row: {
  requestId: string;
  kind: string;
  lessonIdInput: string;
  lessonIdResolved: string | null;
  model: string;
  fallback: boolean;
  slotCount: number;
  inputJson: string;
  outputJson: string | null;
  errorText: string | null;
}): void {
  try {
    ensureAiQuestionGenerationsTable();
    db.prepare(
      `INSERT INTO ai_question_generations (
        request_id, kind, lesson_id_input, lesson_id_resolved, model, fallback, slot_count, input_json, output_json, error_text
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ).run(
      row.requestId,
      row.kind,
      row.lessonIdInput,
      row.lessonIdResolved,
      row.model,
      row.fallback ? 1 : 0,
      row.slotCount,
      row.inputJson,
      row.outputJson,
      row.errorText
    );
  } catch (e) {
    console.error('persistAiQuestionGeneration failed:', e);
  }
}
