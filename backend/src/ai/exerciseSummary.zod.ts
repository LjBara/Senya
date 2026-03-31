import { z } from 'zod';
import { lessonContextSchema } from './remediationSlots.zod.js';

export const exerciseWrongQuestionSchema = z.object({
  type: z.string().max(80),
  summary: z.string().max(500),
});

export const exerciseSummaryBodySchema = z
  .object({
    lessonId: z.string().min(1).max(200),
    lessonContext: lessonContextSchema,
    exerciseTitle: z.string().min(1).max(200),
    score: z.coerce.number().int().min(0),
    totalQuestions: z.coerce.number().int().min(1),
    wrongQuestions: z.array(exerciseWrongQuestionSchema).max(25).default([]),
  })
  .strict()
  .refine((d) => d.score <= d.totalQuestions, {
    message: 'score must not exceed totalQuestions',
    path: ['score'],
  });

export type ExerciseSummaryBody = z.infer<typeof exerciseSummaryBodySchema>;

/** Parsed model output after Gemini returns JSON. */
export const exerciseSummaryOutputSchema = z.object({
  summary: z.string().min(1).max(600),
  recommendedSubtopics: z.array(z.string().max(100)).max(5),
});

export type ExerciseSummaryOutput = z.infer<typeof exerciseSummaryOutputSchema>;
