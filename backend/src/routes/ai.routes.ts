import express from 'express';
import { generateQuizReplacements } from '../services/aiQuiz.service.js';

const router = express.Router();

router.post('/generate-quiz', async (req, res) => {
  // #region agent log
  fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-Debug-Session-Id': '78613b',
    },
    body: JSON.stringify({
      sessionId: '78613b',
      hypothesisId: 'H1_H2',
      location: 'ai.routes.ts:POST/generate-quiz',
      message: 'handler entered',
      data: {
        origin: req.headers.origin ?? '(none)',
        host: req.headers.host,
      },
      timestamp: Date.now(),
    }),
  }).catch(() => {});
  // #endregion
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

export default router;
