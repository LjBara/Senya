import type { RemediationSlot } from './remediationSlots.zod.js';
import { lessonContextToPromptBlock, mergeLessonContext } from '../services/lessonResolve.service.js';

type MergedCtx = ReturnType<typeof mergeLessonContext>;

const SHAPE_EXAMPLES = `
Every element of "questions" MUST be a full object (never {} or placeholders). Example for a multiple_choice slot:
{"type":"multiple_choice","question":"How many dots are there?","options":["3","4","5","6"],"correctAnswer":3,"explanation":"There are 6 dots; index 3 is the fourth option."}
Example for fill_blank:
{"type":"fill_blank","question":"Count: 2, 3, __, 5","correctAnswer":"4","explanation":"The missing number is 4."}
`.trim();

const TYPE_RULES = `
For EACH item i (0-based), the "type" field MUST exactly match remediation slot i type.

multiple_choice OR circle_answer:
{ "type": "multiple_choice" | "circle_answer", "question": string, "options": string[] (3-6 distinct strings),
  "correctAnswer": integer 0-based index into options (first option = 0), "explanation": string,
  optional "objects": string[] (emoji), optional "objectCount": number }

fill_blank OR write_number:
{ "type": same as slot, "question": string, "correctAnswer": string, "explanation": string }

true_false:
{ "type": "true_false", "question": string, "correctAnswer": boolean, "explanation": string }

matching:
{ "type": "matching", "question": string, "leftItems": string[], "rightItems": string[] (same length as leftItems),
  "correctMatches": number[] (length = leftItems; index i = which rightItems index matches left i), "explanation": string }

drag_drop:
{ "type": "drag_drop", "question": string, "sequence": string[] (use "__" for blanks),
  "availableNumbers": string[], "correctAnswer": string[] (values for blanks in order),
  "blankPositions": number[] (indices in sequence where blanks are), "explanation": string }
`.trim();

export function buildRemediationPrompt(merged: MergedCtx, slots: RemediationSlot[]): string {
  const slotsJson = JSON.stringify(
    slots.map((s, i) => ({
      index: i,
      type: s.type,
      summary: s.summary,
      skills: s.skills,
      difficulty: s.difficulty,
      objectCountHint: s.objectCountHint,
    })),
    null,
    0
  );

  return `You are generating math practice items for elementary students.

${lessonContextToPromptBlock(merged)}

Remediation slots (generate EXACTLY one question per slot, same order, same types):
${slotsJson}

${SHAPE_EXAMPLES}

${TYPE_RULES}

Rules:
1. Return ONLY valid JSON: one object with key "questions" whose value is an array of length ${slots.length}.
2. questions[i].type MUST equal slot i type from the list above.
3. Each questions[i] MUST be a complete object with all required fields for that type. Never output an empty object.
4. Use new numbers/wording vs slot summaries; keep difficulty and skills aligned.
5. Options must be distinct strings. correctAnswer for MC/circle is the INDEX (0-based), not the text.
6. Use the field name "options" (array of strings), not "choices". Use "question" for the stem, not "stem" or "prompt".
7. No markdown, no code fences, no text outside the JSON object.`;
}
