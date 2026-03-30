import express from 'express';
import { generateQuizReplacements, generateQuestionsFromBody } from '../services/aiQuestionGeneration.service.js';
import { generateQuestionsBodySchema } from '../ai/remediationSlots.zod.js';

const router = express.Router();

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
  // #region agent log
  fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-req',location:'ai.routes.ts:generate-questions:entry',message:'handler entered',data:{hasBody:!!req.body,slotCount:Array.isArray((req.body as any)?.remediationSlots)?(req.body as any).remediationSlots.length:-1},timestamp:Date.now()})}).catch(()=>{});
  // #endregion
  try {
    const parsed = generateQuestionsBodySchema.safeParse(req.body ?? {});
    if (!parsed.success) {
      // #region agent log
      fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-zod',location:'ai.routes.ts:zod-fail',message:'body validation failed',data:{issues:parsed.error.issues.slice(0,5).map(i=>({path:i.path.join('.'),msg:i.message}))},timestamp:Date.now()})}).catch(()=>{});
      // #endregion
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

    // #region agent log
    fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-result',location:'ai.routes.ts:before-json',message:'generation returned',data:{qLen:result.questions.length,fallback:result.fallback,hasError:!!result.error,requestId:result.requestId},timestamp:Date.now()})}).catch(()=>{});
    // #endregion
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
      // #region agent log
      fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-json',location:'ai.routes.ts:serialize-fail',message:'JSON.stringify(payload) failed',data:{err:String(serErr)},timestamp:Date.now()})}).catch(()=>{});
      // #endregion
      throw serErr;
    }
    return res.json(payload);
  } catch (e) {
    const errMsg = e instanceof Error ? e.message : String(e);
    const errStack = e instanceof Error ? e.stack?.slice(0, 800) : '';
    console.error('POST /generate-questions:', e);
    // #region agent log
    fetch('http://127.0.0.1:7383/ingest/e03b75a4-c4bb-47a1-9e2e-f8306fa1b631',{method:'POST',headers:{'Content-Type':'application/json','X-Debug-Session-Id':'df25fd'},body:JSON.stringify({sessionId:'df25fd',runId:'pre-fix',hypothesisId:'H-500',location:'ai.routes.ts:catch',message:'uncaught exception',data:{errMsg,errStack},timestamp:Date.now()})}).catch(()=>{});
    // #endregion
    return res.status(500).json({
      success: false,
      error: 'Failed to generate questions',
      questions: [],
      requestId: '',
    });
  }
});

export default router;
