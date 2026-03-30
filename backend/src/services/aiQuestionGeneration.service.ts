import { randomUUID } from 'crypto';
import {
  mergeLessonContext,
  resolveLessonRecord,
} from './lessonResolve.service.js';
import { buildRemediationPrompt } from '../ai/prompts.js';
import {
  generateContentPlain,
  generateContentWithJson,
  getResolvedGeminiModel,
  parseJsonFromModel,
} from '../ai/geminiClient.js';
import {
  inspectFirstUnparsedSlot,
  mergeRemediationWithFallback,
  validateOrderedQuestions,
} from '../ai/generatedQuestion.zod.js';
import type { RemediationSlot } from '../ai/remediationSlots.zod.js';
import type { ClientLessonContext } from '../ai/remediationSlots.zod.js';
import {
  persistAiQuestionGeneration,
  persistGeneratedQuizLegacy,
  sanitizeSlotsForAudit,
} from './aiAudit.service.js';
import { createRequestLogger } from '../ai/logger.js';
import { legacyIncorrectToSlots, legacyStringToLessonContext } from '../ai/legacyAdapter.js';
import {
  finalizeAiGenerationLogFile,
  upsertAiGenerationLog,
} from '../util/aiGenerationFileLog.js';

function cloneFallbackSource(source: unknown[] | undefined): Record<string, unknown>[] {
  if (!source?.length) return [];
  return source
    .filter((x) => x !== null && typeof x === 'object')
    .map((x) => JSON.parse(JSON.stringify(x)) as Record<string, unknown>);
}

function modelName(): string {
  return getResolvedGeminiModel();
}

export type RemediationResult = {
  questions: Record<string, unknown>[];
  fallback: boolean;
  error?: string;
  requestId: string;
};

/**
 * Core remediation pipeline: resolve lesson, merge context, call Gemini, validate ordered output.
 */
export async function runRemediationGeneration(params: {
  requestId: string;
  lessonIdInput: string;
  clientContext: ClientLessonContext;
  slots: RemediationSlot[];
  originalIncorrectQuestions?: unknown[];
  log: ReturnType<typeof createRequestLogger>;
}): Promise<RemediationResult> {
  const { requestId, lessonIdInput, clientContext, slots, originalIncorrectQuestions, log } = params;

  // #region agent log
  fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-pipe',location:'aiQuestionGeneration.service.ts:runRemediation:entry',message:'pipeline start',data:{requestId,lessonIdInput,slotCount:slots.length,origLen:originalIncorrectQuestions?.length??-1},timestamp:Date.now()})}).catch(()=>{});
  // #endregion

  const resolved = resolveLessonRecord(lessonIdInput, {
    lessonTitle: clientContext.lessonTitle,
    subtopics: clientContext.subtopics,
  });
  // #region agent log
  fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-DB',location:'aiQuestionGeneration.service.ts:after-resolve',message:'lesson resolved',data:{resolved:!!resolved,resolvedId:resolved?.id??null},timestamp:Date.now()})}).catch(()=>{});
  // #endregion
  if (!resolved) {
    log.warn('lesson not found in DB; using client context only', { lessonIdInput });
  }

  const merged = mergeLessonContext(resolved, clientContext);
  const lessonIdForStorage = merged.resolvedLessonId ?? lessonIdInput;

  const auditInput = sanitizeSlotsForAudit(slots);

  if (slots.length === 0) {
    persistAiQuestionGeneration({
      requestId,
      kind: 'remediation',
      lessonIdInput,
      lessonIdResolved: merged.resolvedLessonId,
      model: modelName(),
      fallback: false,
      slotCount: 0,
      inputJson: auditInput,
      outputJson: JSON.stringify([]),
      errorText: null,
    });
    return { questions: [], fallback: false, requestId };
  }

  const fallbackClones = cloneFallbackSource(originalIncorrectQuestions);
  const canUseFallback =
    fallbackClones.length === slots.length && fallbackClones.length > 0;

  if (!process.env.GEMINI_API_KEY?.trim()) {
    const out = canUseFallback ? fallbackClones : [];
    const error = 'GEMINI_API_KEY is not configured';
    persistAiQuestionGeneration({
      requestId,
      kind: 'remediation',
      lessonIdInput,
      lessonIdResolved: merged.resolvedLessonId,
      model: modelName(),
      fallback: true,
      slotCount: slots.length,
      inputJson: auditInput,
      outputJson: out.length ? JSON.stringify(out) : null,
      errorText: error,
    });
    return { questions: out, fallback: true, error, requestId };
  }

  const prompt = buildRemediationPrompt(merged, slots);

  let lastGeminiError: string | undefined;
  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      let text: string;
      try {
        text = await generateContentWithJson(prompt, log);
      } catch (e1) {
        log.warn('json generation path failed, trying plain', {
          attempt,
          err: e1 instanceof Error ? e1.message : String(e1),
        });
        text = await generateContentPlain(
          `${prompt}\n\nRespond with only a JSON object with a single key "questions" (array). No markdown.`,
          log
        );
      }

      const parsed = parseJsonFromModel(text);
      const validated = validateOrderedQuestions(slots, parsed);
      const partialForLog =
        canUseFallback && !validated
          ? mergeRemediationWithFallback(slots, parsed, fallbackClones)
          : null;
      const diag = validated ? undefined : inspectFirstUnparsedSlot(slots, parsed);

      upsertAiGenerationLog(
        requestId,
        { lessonIdInput, model: modelName(), slotCount: slots.length },
        (prev) => {
          const snap = {
            attempt,
            modelParsed: parsed,
            strictValidated: validated !== null,
            firstSlotFailure: diag ?? undefined,
            mergeAiFilledCount: partialForLog?.aiFilledCount,
          };
          if (prev && prev.requestId === requestId) {
            return {
              ...prev,
              updatedAt: new Date().toISOString(),
              attempts: [...prev.attempts, snap],
            };
          }
          const iso = new Date().toISOString();
          return {
            requestId,
            lessonIdInput,
            model: modelName(),
            slotCount: slots.length,
            createdAt: iso,
            updatedAt: iso,
            attempts: [snap],
          };
        }
      );

      if (validated) {
        finalizeAiGenerationLogFile(requestId, {
          fallback: false,
          questionCount: validated.length,
          questions: validated as unknown[],
        });
        persistGeneratedQuizLegacy(lessonIdForStorage, validated);
        persistAiQuestionGeneration({
          requestId,
          kind: 'remediation',
          lessonIdInput,
          lessonIdResolved: merged.resolvedLessonId,
          model: modelName(),
          fallback: false,
          slotCount: slots.length,
          inputJson: auditInput,
          outputJson: JSON.stringify(validated),
          errorText: null,
        });
        return { questions: validated, fallback: false, requestId };
      }

      if (canUseFallback) {
        const partial = partialForLog;
        if (partial && (partial.aiFilledCount > 0 || attempt === 3)) {
          finalizeAiGenerationLogFile(requestId, {
            fallback: true,
            questionCount: partial.questions.length,
            questions: partial.questions as unknown[],
            error: partial.aiFilledCount === 0 ? 'all slots fell back to originals' : undefined,
          });
          persistGeneratedQuizLegacy(lessonIdForStorage, partial.questions);
          const allFallback = partial.aiFilledCount === 0;
          const someFallback = partial.aiFilledCount < slots.length && partial.aiFilledCount > 0;
          persistAiQuestionGeneration({
            requestId,
            kind: 'remediation',
            lessonIdInput,
            lessonIdResolved: merged.resolvedLessonId,
            model: modelName(),
            fallback: true,
            slotCount: slots.length,
            inputJson: auditInput,
            outputJson: JSON.stringify(partial.questions),
            errorText: allFallback
              ? 'strict validation failed; per-slot merge all originals'
              : someFallback
                ? 'strict validation failed; partial AI merge'
                : 'partial AI merge (all slots parsed)',
          });
          return {
            questions: partial.questions,
            fallback: allFallback || someFallback,
            requestId,
            ...(allFallback && attempt === 3
              ? {
                  error:
                    'AI generation failed after retries; returning original incorrect questions',
                }
              : someFallback
                ? {
                    error:
                      'Some questions were kept from your missed items; others are new practice questions.',
                  }
                : {}),
          };
        }
      }

      log.warn('ordered validation failed', { attempt });
    } catch (e) {
      lastGeminiError = e instanceof Error ? e.message : String(e);
      log.error(`remediation attempt ${attempt}`, {
        err: lastGeminiError,
      });
    }
  }

  const quotaOr429 =
    lastGeminiError &&
    (/429/.test(lastGeminiError) || /quota/i.test(lastGeminiError));
  const errMsg = quotaOr429
    ? `Gemini API quota or rate limit (model ${modelName()}). Free tier often has no quota for gemini-2.0-flash; use default gemini-2.5-flash, try GEMINI_MODEL=gemini-2.5-flash-lite, or enable billing. New API keys in the same Google Cloud project share the same quota.`
    : 'AI generation failed after retries; returning original incorrect questions';
  const out = canUseFallback ? fallbackClones : [];
  finalizeAiGenerationLogFile(requestId, {
    fallback: true,
    error: errMsg,
    questionCount: out.length,
    questions: out as unknown[],
  });
  persistAiQuestionGeneration({
    requestId,
    kind: 'remediation',
    lessonIdInput,
    lessonIdResolved: merged.resolvedLessonId,
    model: modelName(),
    fallback: true,
    slotCount: slots.length,
    inputJson: auditInput,
    outputJson: out.length ? JSON.stringify(out) : null,
    errorText: errMsg,
  });
  return {
    questions: out,
    fallback: true,
    error: canUseFallback ? errMsg : `${errMsg} (no originalIncorrectQuestions provided)`,
    requestId,
  };
}

/** Legacy `POST /generate-quiz` — same response shape for existing clients. */
export async function generateQuizReplacements(
  lessonId: string,
  lessonContext: string,
  incorrectQuestions: unknown[]
): Promise<{ questions: Record<string, unknown>[]; fallback: boolean; error?: string }> {
  const incorrect = Array.isArray(incorrectQuestions) ? incorrectQuestions : [];
  if (incorrect.length === 0) {
    return { questions: [], fallback: false };
  }

  const requestId = randomUUID();
  const log = createRequestLogger(requestId);
  const slots = legacyIncorrectToSlots(incorrect);
  const clientContext = legacyStringToLessonContext(lessonContext);

  const result = await runRemediationGeneration({
    requestId,
    lessonIdInput: lessonId.trim(),
    clientContext,
    slots,
    originalIncorrectQuestions: incorrect,
    log,
  });

  return {
    questions: result.questions,
    fallback: result.fallback,
    ...(result.error ? { error: result.error } : {}),
  };
}

export async function generateQuestionsFromBody(body: {
  kind: 'remediation' | 'lesson_practice' | 'assessment';
  lessonId: string;
  lessonContext: ClientLessonContext;
  remediationSlots: RemediationSlot[];
  originalIncorrectQuestions?: unknown[];
}): Promise<RemediationResult> {
  const requestId = randomUUID();
  const log = createRequestLogger(requestId);

  if (body.kind !== 'remediation') {
    persistAiQuestionGeneration({
      requestId,
      kind: body.kind,
      lessonIdInput: body.lessonId,
      lessonIdResolved: null,
      model: modelName(),
      fallback: false,
      slotCount: 0,
      inputJson: JSON.stringify({ kind: body.kind }),
      outputJson: null,
      errorText: 'kind not implemented',
    });
    return {
      questions: [],
      fallback: false,
      error: `kind "${body.kind}" is not implemented yet`,
      requestId,
    };
  }

  return runRemediationGeneration({
    requestId,
    lessonIdInput: body.lessonId.trim(),
    clientContext: body.lessonContext,
    slots: body.remediationSlots,
    originalIncorrectQuestions: body.originalIncorrectQuestions,
    log,
  });
}
