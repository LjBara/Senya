import { GoogleGenerativeAI } from '@google/generative-ai';
import db from '../db/connection.js';

export type MCQuestion = {
  id: number;
  type: 'multiple_choice';
  question: string;
  options: number[];
  correctAnswer: number;
  explanation: string;
  objects?: string[];
  objectCount?: number;
};

// Use a model id valid for v1beta generateContent (gemini-1.5-flash returns 404 on many keys).
const DEFAULT_MODEL = 'gemini-2.0-flash';

function stripCodeFences(text: string): string {
  let t = text.trim();
  const fence = /^```(?:json)?\s*([\s\S]*?)```$/m.exec(t);
  if (fence) t = fence[1].trim();
  return t;
}

function parseJsonFromModel(text: string): unknown {
  const cleaned = stripCodeFences(text);
  return JSON.parse(cleaned) as unknown;
}

function isFiniteNumber(n: unknown): n is number {
  return typeof n === 'number' && Number.isFinite(n);
}

function validateAndNormalizeQuestions(
  raw: unknown,
  minCount: number,
  maxCount: number
): MCQuestion[] | null {
  if (raw === null || typeof raw !== 'object') return null;
  const obj = raw as Record<string, unknown>;
  const arr = obj.questions;
  if (!Array.isArray(arr) || arr.length < minCount || arr.length > maxCount) return null;

  const out: MCQuestion[] = [];
  for (let i = 0; i < arr.length; i++) {
    const q = arr[i];
    if (q === null || typeof q !== 'object') return null;
    const item = q as Record<string, unknown>;

    if (item.type !== 'multiple_choice') return null;
    if (typeof item.question !== 'string' || !item.question.trim()) return null;
    if (typeof item.explanation !== 'string') return null;

    const optionsRaw = item.options;
    if (!Array.isArray(optionsRaw) || optionsRaw.length < 4 || optionsRaw.length > 5) return null;
    const options: number[] = [];
    for (const o of optionsRaw) {
      if (!isFiniteNumber(o)) return null;
      options.push(Math.trunc(o));
    }
    const unique = new Set(options);
    if (unique.size !== options.length) return null;

    if (!isFiniteNumber(item.correctAnswer)) return null;
    const correctAnswer = Math.trunc(item.correctAnswer);
    if (correctAnswer < 0 || correctAnswer >= options.length) return null;

    const correctValue = options[correctAnswer];
    const sameValueCount = options.filter((x) => x === correctValue).length;
    if (sameValueCount > 1) return null;

    const normalized: MCQuestion = {
      id: i + 1,
      type: 'multiple_choice',
      question: item.question.trim(),
      options,
      correctAnswer,
      explanation: item.explanation.trim(),
    };

    if (item.objects !== undefined) {
      if (!Array.isArray(item.objects)) return null;
      const objects: string[] = [];
      for (const s of item.objects) {
        if (typeof s !== 'string') return null;
        objects.push(s);
      }
      normalized.objects = objects;
    }
    if (item.objectCount !== undefined) {
      if (!isFiniteNumber(item.objectCount)) return null;
      normalized.objectCount = Math.trunc(item.objectCount);
    }

    out.push(normalized);
  }
  return out;
}

function buildPrompt(
  lessonContext: string,
  incorrectQuestions: unknown[],
  targetCount: number
): string {
  return `You are generating math quiz items for elementary students. Output ONLY valid JSON, no markdown.

Lesson context:
${lessonContext}

The student missed these questions (JSON). Use them only as inspiration — same skills and difficulty, but change numbers and emoji/objects (e.g. apple → orange):
${JSON.stringify(incorrectQuestions)}

Rules:
1. Return a JSON object with a single key "questions" (array).
2. Produce exactly ${targetCount} items.
3. Each item MUST be multiple_choice with this shape:
   {
     "id": <number 1..n>,
     "type": "multiple_choice",
     "question": string,
     "options": number[] (length 4 or 5, all integers, all distinct values),
     "correctAnswer": integer INDEX into options (0-based), NOT the numeric answer value,
     "explanation": string
   }
4. If a source question had "objects" (emoji array) and "objectCount", include "objects" and "objectCount" on the new item when it is a counting/visual question.
5. Stay strictly within the lesson context. Same difficulty as the missed items.
6. Do not include any text outside the JSON object.`;
}

function ensureGeneratedQuizzesTable(): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS generated_quizzes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      lesson_id TEXT,
      questions_json TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
  `);
}

function persistGeneratedQuiz(lessonId: string, questions: MCQuestion[]): void {
  try {
    ensureGeneratedQuizzesTable();
    db.prepare(
      `INSERT INTO generated_quizzes (lesson_id, questions_json) VALUES (?, ?)`
    ).run(lessonId, JSON.stringify(questions));
  } catch (e) {
    console.error('persistGeneratedQuiz failed:', e);
  }
}

async function callGemini(prompt: string): Promise<string> {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('GEMINI_API_KEY is not set');

  const modelName = process.env.GEMINI_MODEL?.trim() || DEFAULT_MODEL;
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: modelName });
  const result = await model.generateContent(prompt);
  const text = result.response.text();
  if (!text) throw new Error('Empty model response');
  return text;
}

function cloneIncorrectForFallback(incorrect: unknown[]): Record<string, unknown>[] {
  return incorrect
    .filter((x) => x !== null && typeof x === 'object')
    .map((x) => JSON.parse(JSON.stringify(x)) as Record<string, unknown>);
}

export async function generateQuizReplacements(
  lessonId: string,
  lessonContext: string,
  incorrectQuestions: unknown[]
): Promise<{ questions: Record<string, unknown>[]; fallback: boolean; error?: string }> {
  const incorrect = Array.isArray(incorrectQuestions) ? incorrectQuestions : [];
  if (incorrect.length === 0) {
    return { questions: [], fallback: false };
  }

  const fallbackPayload = cloneIncorrectForFallback(incorrect);

  if (!process.env.GEMINI_API_KEY?.trim()) {
    return {
      questions: fallbackPayload,
      fallback: true,
      error: 'GEMINI_API_KEY is not configured',
    };
  }

  const targetCount = incorrect.length + Math.ceil(incorrect.length * 0.3);
  const maxCount = targetCount + 2;
  const prompt = buildPrompt(lessonContext, incorrect, targetCount);

  for (let attempt = 1; attempt <= 3; attempt++) {
    try {
      const text = await callGemini(prompt);
      const parsed = parseJsonFromModel(text);
      const validated = validateAndNormalizeQuestions(parsed, targetCount, maxCount);
      if (!validated) {
        const loose = validateAndNormalizeQuestions(parsed, incorrect.length, maxCount);
        if (loose && loose.length >= incorrect.length) {
          const trimmed =
            loose.length > targetCount ? loose.slice(0, targetCount) : loose;
          persistGeneratedQuiz(lessonId, trimmed);
          return { questions: trimmed as unknown as Record<string, unknown>[], fallback: false };
        }
        continue;
      }
      const trimmed =
        validated.length > targetCount ? validated.slice(0, targetCount) : validated;
      persistGeneratedQuiz(lessonId, trimmed);
      return { questions: trimmed as unknown as Record<string, unknown>[], fallback: false };
    } catch (e) {
      console.error(`generateQuizReplacements attempt ${attempt}:`, e);
    }
  }

  return {
    questions: fallbackPayload,
    fallback: true,
    error: 'AI generation failed after retries; returning original incorrect questions',
  };
}
