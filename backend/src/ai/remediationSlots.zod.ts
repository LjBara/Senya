import { z } from 'zod';

const slotBase = {
  summary: z.string().min(1),
  skills: z.array(z.string()).optional(),
  difficulty: z.string().optional(),
  objectCountHint: z.number().int().optional(),
};

export const remediationSlotSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('multiple_choice'), ...slotBase }),
  z.object({ type: z.literal('circle_answer'), ...slotBase }),
  z.object({ type: z.literal('fill_blank'), ...slotBase }),
  z.object({ type: z.literal('write_number'), ...slotBase }),
  z.object({ type: z.literal('true_false'), ...slotBase }),
  z.object({ type: z.literal('matching'), ...slotBase }),
  z.object({ type: z.literal('drag_drop'), ...slotBase }),
]);

export type RemediationSlot = z.infer<typeof remediationSlotSchema>;

export const lessonContextSchema = z
  .object({
    topicId: z.string().optional(),
    topicTitle: z.string().optional(),
    lessonTitle: z.string().optional(),
    subtopics: z.array(z.string()).optional(),
    gradeLevel: z.string().optional(),
    locale: z.string().optional(),
    constraints: z.array(z.string()).optional(),
    vocabulary: z.array(z.string()).optional(),
    notes: z.array(z.string()).optional(),
  })
  .strict()
  .default({});

export type ClientLessonContext = z.infer<typeof lessonContextSchema>;

export const generateQuestionsBodySchema = z.object({
  kind: z.enum(['remediation', 'lesson_practice', 'assessment']),
  lessonId: z.string().min(1),
  lessonContext: lessonContextSchema,
  remediationSlots: z.array(remediationSlotSchema),
  /** Same order as slots; used when AI fails so the client still receives clones (optional). */
  originalIncorrectQuestions: z.array(z.unknown()).optional(),
});

export type GenerateQuestionsBody = z.infer<typeof generateQuestionsBodySchema>;
