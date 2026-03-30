import express from 'express';
import { generateQuizReplacements, generateQuestionsFromBody } from '../services/aiQuestionGeneration.service.js';
import { generateQuestionsBodySchema } from '../ai/remediationSlots.zod.js';

const router = express.Router();

// @deprecated Use POST /ai/generate-questions instead. This endpoint accepts
// a plain-string lessonContext and is kept only for backward-compatible clients.
// New exercise integrations should use the structured /generate-questions route.
router.post('/generate-quiz', async (req, res) => {
  try {
    const { lessonId, lessonContext, incorrectQuestions } = req.body ?? {};

    if (typeof lessonId !== 'string' || !lessonId.trim()) {
      return res.status(400).json({
        success: false,
        error: 'lessonId is required (string)',
        questions: [],
      });
    }
    if (typeof lessonContext !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'lessonContext is required (string)',
        questions: [],
      });
    }
    if (!Array.isArray(incorrectQuestions)) {
      return res.status(400).json({
        success: false,
        error: 'incorrectQuestions is required (array)',
        questions: [],
      });
    }

    const result = await generateQuizReplacements(
      lessonId.trim(),
      lessonContext,
      incorrectQuestions
    );

    return res.json({
      success: true,
      questions: result.questions,
      fallback: result.fallback,
      ...(result.error ? { error: result.error } : {}),
    });
  } catch (e) {
    console.error('POST /generate-quiz:', e);
    return res.status(500).json({
      success: false,
      error: 'Failed to generate quiz',
      questions: [],
    });
  }
});

router.post('/generate-questions', async (req, res) => {
  try {
    const parsed = generateQuestionsBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      return res.status(400).json({
        success: false,
        error: parsed.error.issues.map((i) => i.message).join('; ') || 'Invalid request body',
        questions: [],
        requestId: '',
      });
    }

    const body = parsed.data;
    if (body.kind !== 'remediation') {
      return res.status(501).json({
        success: false,
        error: `kind "${body.kind}" is not implemented yet`,
        questions: [],
        requestId: '',
      });
    }

    let originals = body.originalIncorrectQuestions;
    if (originals && originals.length !== body.remediationSlots.length) {
      originals = undefined;
    }

    const result = await generateQuestionsFromBody({
      kind: body.kind,
      lessonId: body.lessonId,
      lessonContext: body.lessonContext,
      remediationSlots: body.remediationSlots,
      originalIncorrectQuestions: originals,
    });

    let payload: Record<string, unknown>;
    try {
      payload = {
        success: true,
        questions: result.questions,
        fallback: result.fallback,
        requestId: result.requestId,
        ...(result.error ? { error: result.error } : {}),
      };
      JSON.stringify(payload);
    } catch (serErr) {
      throw serErr;
    }
    return res.json(payload);
  } catch (e) {
    console.error('POST /generate-questions:', e);
    return res.status(500).json({
      success: false,
      error: 'Failed to generate questions',
      questions: [],
      requestId: '',
    });
  }
});

export default router;
