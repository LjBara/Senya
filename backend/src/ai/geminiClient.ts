import { GoogleGenerativeAI } from '@google/generative-ai';
import type { RequestLogger } from './logger.js';

/** Free tier often has 0 quota for 2.0-flash; 2.5-flash is the current default on the developer free tier. */
const DEFAULT_MODEL = 'gemini-2.5-flash';

let warnedGemini20Flash = false;

/** Effective model: maps deprecated zero-quota `gemini-2.0-flash` from .env to DEFAULT_MODEL (runtime evidence: limit:0 on free tier). */
export function getResolvedGeminiModel(): string {
  const raw = process.env.GEMINI_MODEL?.trim();
  if (!raw) return DEFAULT_MODEL;
  if (raw === 'gemini-2.0-flash') {
    if (!warnedGemini20Flash) {
      warnedGemini20Flash = true;
      console.warn(
        `[Gemini] GEMINI_MODEL=gemini-2.0-flash has no free-tier quota. Using ${DEFAULT_MODEL}. Remove GEMINI_MODEL or set GEMINI_MODEL=${DEFAULT_MODEL} in backend/.env.local.`
      );
    }
    return DEFAULT_MODEL;
  }
  return raw;
}

function getGeminiApiKey(): string {
  const k = process.env.GEMINI_API_KEY?.trim();
  if (!k) throw new Error('GEMINI_API_KEY is not set');
  return k;
}

export function stripCodeFences(text: string): string {
  let t = text.trim();
  const fence = /^```(?:json)?\s*([\s\S]*?)```$/m.exec(t);
  if (fence) t = fence[1].trim();
  return t;
}

export function parseJsonFromModel(text: string): unknown {
  const cleaned = stripCodeFences(text);
  return JSON.parse(cleaned) as unknown;
}

/**
 * JSON mode without responseSchema. Do NOT use responseSchema with `items: { type: OBJECT }` and no
 * `properties` — Gemini returns an array of empty `{}` (see ai-generations logs: rawKeys []).
 */
export async function generateContentWithJson(
  prompt: string,
  log: RequestLogger
): Promise<string> {
  const apiKey = getGeminiApiKey();

  const modelName = getResolvedGeminiModel();
  const genAI = new GoogleGenerativeAI(apiKey);

  const model = genAI.getGenerativeModel({
    model: modelName,
    generationConfig: {
      responseMimeType: 'application/json',
    },
  });

  const started = Date.now();
  const result = await model.generateContent(prompt);
  const text = result.response.text();
  if (!text) throw new Error('Empty model response');
  log.info('gemini ok (json mime)', { ms: Date.now() - started, model: modelName });
  return text;
}

export async function generateContentPlain(prompt: string, log: RequestLogger): Promise<string> {
  const apiKey = getGeminiApiKey();

  const modelName = getResolvedGeminiModel();
  const genAI = new GoogleGenerativeAI(apiKey);
  const model = genAI.getGenerativeModel({ model: modelName });
  const started = Date.now();
  const result = await model.generateContent(prompt);
  const text = result.response.text();
  if (!text) throw new Error('Empty model response');
  log.info('gemini ok (plain)', { ms: Date.now() - started, model: modelName });
  return text;
}
