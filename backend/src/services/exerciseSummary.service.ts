import { randomUUID } from 'crypto';
import {
  mergeLessonContext,
  resolveLessonRecord,
} from './lessonResolve.service.js';
import { buildExerciseSummaryPrompt } from '../ai/exerciseSummaryPrompt.js';
import {
  exerciseSummaryOutputSchema,
  type ExerciseSummaryBody,
} from '../ai/exerciseSummary.zod.js';
import {
  generateContentPlain,
  generateContentWithJson,
  getResolvedGeminiModel,
  parseJsonFromModel,
} from '../ai/geminiClient.js';
import { createRequestLogger } from '../ai/logger.js';
import { persistAiQuestionGeneration } from './aiAudit.service.js';

export type ExerciseSummaryResult = {
  success: true;
  summary: string;
  recommendedSubtopics: string[];
  requestId: string;
};

export type ExerciseSummaryFailure = {
  success: false;
  error: string;
  requestId: string;
};

function modelName(): string {
  return getResolvedGeminiModel();
}

function sanitizeInputForAudit(body: ExerciseSummaryBody): string {
  return JSON.stringify({
    exerciseTitle: body.exerciseTitle,
    score: body.score,
    totalQuestions: body.totalQuestions,
    wrongCount: body.wrongQuestions.length,
    wrongQuestions: body.wrongQuestions.map((w) => ({
      type: w.type,
      summary: w.summary.slice(0, 200),
    })),
  });
}

function clampOutput(parsed: {
  summary: string;
  recommendedSubtopics: string[];
}): { summary: string; recommendedSubtopics: string[] } {
  const summary =
    parsed.summary.length > 600 ? parsed.summary.slice(0, 597) + '...' : parsed.summary;
  const topics = parsed.recommendedSubtopics
    .slice(0, 5)
    .map((t) => (t.length > 100 ? t.slice(0, 97) + '...' : t));
  return { summary, recommendedSubtopics: topics };
}

/**
 * Resolves lesson, calls Gemini with JSON output, validates with Zod, audits to SQLite.
 */
export async function runExerciseSummaryGeneration(
  body: ExerciseSummaryBody
): Promise<ExerciseSummaryResult | ExerciseSummaryFailure> {
  const requestId = randomUUID();
  const log = createRequestLogger(requestId);
  const lessonIdInput = body.lessonId.trim();
  const auditInput = sanitizeInputForAudit(body);

  const resolved = resolveLessonRecord(lessonIdInput, {
    lessonTitle: body.lessonContext.lessonTitle,
    subtopics: body.lessonContext.subtopics,
  });
  if (!resolved) {
    log.warn('lesson not found in DB; using client context only', { lessonIdInput });
  }

  const merged = mergeLessonContext(resolved, body.lessonContext);
  const prompt = buildExerciseSummaryPrompt(merged, {
    exerciseTitle: body.exerciseTitle,
    score: body.score,
    totalQuestions: body.totalQuestions,
    wrongQuestions: body.wrongQuestions,
  });

  if (!process.env.GEMINI_API_KEY?.trim()) {
    const error = 'GEMINI_API_KEY is not configured';
    persistAiQuestionGeneration({
      requestId,
      kind: 'exercise_summary',
      lessonIdInput,
      lessonIdResolved: merged.resolvedLessonId,
      model: modelName(),
      fallback: true,
      slotCount: body.wrongQuestions.length,
      inputJson: auditInput,
      outputJson: null,
      errorText: error,
    });
    return { success: false, error, requestId };
  }

  const persistError = (errorText: string) => {
    persistAiQuestionGeneration({
      requestId,
      kind: 'exercise_summary',
      lessonIdInput,
      lessonIdResolved: merged.resolvedLessonId,
      model: modelName(),
      fallback: true,
      slotCount: body.wrongQuestions.length,
      inputJson: auditInput,
      outputJson: null,
      errorText,
    });
  };

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      let text: string;
      try {
        text = await generateContentWithJson(prompt, log);
      } catch (e1) {
        log.warn('exercise summary json path failed, trying plain', {
          attempt,
          err: e1 instanceof Error ? e1.message : String(e1),
        });
        text = await generateContentPlain(
          `${prompt}\n\nRespond with only a JSON object with keys "summary" (string) and "recommendedSubtopics" (array of strings). No markdown.`,
          log
        );
      }

      let raw: unknown;
      try {
        raw = parseJsonFromModel(text);
      } catch (parseErr) {
        log.warn('exercise summary JSON parse failed', {
          attempt,
          err: parseErr instanceof Error ? parseErr.message : String(parseErr),
        });
        if (attempt === 3) {
          const msg = 'Model returned invalid JSON';
          persistError(msg);
          return { success: false, error: msg, requestId };
        }
        continue;
      }

      const validated = exerciseSummaryOutputSchema.safeParse(raw);
      if (!validated.success) {
        log.warn('exercise summary output schema failed', {
          attempt,
          issues: validated.error.issues,
        });
        if (attempt === 3) {
          const msg = 'Model output did not match expected shape';
          persistError(msg);
          return { success: false, error: msg, requestId };
        }
        continue;
      }

      const out = clampOutput(validated.data);
      persistAiQuestionGeneration({
        requestId,
        kind: 'exercise_summary',
        lessonIdInput,
        lessonIdResolved: merged.resolvedLessonId,
        model: modelName(),
        fallback: false,
        slotCount: body.wrongQuestions.length,
        inputJson: auditInput,
        outputJson: JSON.stringify(out),
        errorText: null,
      });

      return {
        success: true,
        summary: out.summary,
        recommendedSubtopics: out.recommendedSubtopics,
        requestId,
      };
    } catch (e) {
      const errMsg = e instanceof Error ? e.message : String(e);
      log.error('exercise summary attempt failed', { attempt, err: errMsg });
      if (attempt === 3) {
        persistError(errMsg);
        return { success: false, error: errMsg, requestId };
      }
    }
  }

  persistError('AI summary failed after retries');
  return { success: false, error: 'AI summary failed after retries', requestId };
}
