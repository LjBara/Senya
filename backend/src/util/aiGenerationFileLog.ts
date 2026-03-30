import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const backendRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const LOG_DIR = path.join(backendRoot, 'logs', 'ai-generations');

export type AiGenAttemptSnapshot = {
  attempt: number;
  /** Full object returned by JSON.parse from the model (usually `{ questions: [...] }`). */
  modelParsed: unknown;
  strictValidated: boolean;
  /** First slot parse error hint (if any). */
  firstSlotFailure?: { index: number; expectedType: string; rawKeys: string[] };
  mergeAiFilledCount?: number;
};

export type AiGenRequestLogDoc = {
  requestId: string;
  lessonIdInput: string;
  model: string;
  slotCount: number;
  createdAt: string;
  updatedAt: string;
  attempts: AiGenAttemptSnapshot[];
  /** Final payload sent to the client (after validation / merge / fallback). */
  final?: {
    fallback: boolean;
    error?: string;
    questionCount: number;
    questions: unknown[];
  };
};

/**
 * Writes human-readable JSON under `backend/logs/ai-generations/` (gitignored).
 * Open the latest `{requestId}.json` to inspect raw model output vs validated output.
 */
export function upsertAiGenerationLog(
  requestId: string,
  meta: Pick<AiGenRequestLogDoc, 'lessonIdInput' | 'model' | 'slotCount'>,
  updater: (prev: AiGenRequestLogDoc | null) => AiGenRequestLogDoc
): void {
  try {
    fs.mkdirSync(LOG_DIR, { recursive: true });
    const filePath = path.join(LOG_DIR, `${requestId}.json`);
    let prev: AiGenRequestLogDoc | null = null;
    if (fs.existsSync(filePath)) {
      try {
        prev = JSON.parse(fs.readFileSync(filePath, 'utf8')) as AiGenRequestLogDoc;
      } catch {
        prev = null;
      }
    }
    const next = updater(prev);
    fs.writeFileSync(filePath, JSON.stringify(next, null, 2), 'utf8');
    const pointer = path.join(LOG_DIR, '_LATEST_REQUEST.txt');
    fs.writeFileSync(
      pointer,
      `${filePath}\nupdated ${next.updatedAt}\n`,
      'utf8'
    );
    console.log(`📝 AI generation log: ${path.relative(backendRoot, filePath)}`);
  } catch (e) {
    console.warn('[aiGenerationFileLog] write failed:', e);
  }
}

export function aiGenerationsLogDir(): string {
  return LOG_DIR;
}

/** Attach the final HTTP payload (what the app uses for the quiz). */
export function finalizeAiGenerationLogFile(
  requestId: string,
  final: NonNullable<AiGenRequestLogDoc['final']>
): void {
  try {
    const filePath = path.join(LOG_DIR, `${requestId}.json`);
    if (!fs.existsSync(filePath)) return;
    const doc = JSON.parse(fs.readFileSync(filePath, 'utf8')) as AiGenRequestLogDoc;
    doc.final = final;
    doc.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, JSON.stringify(doc, null, 2), 'utf8');
  } catch (e) {
    console.warn('[finalizeAiGenerationLogFile]', e);
  }
}
