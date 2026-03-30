/**
 * Maps Flutter TopicsData lesson ids to SQLite `lessons.id` (stable id for fresh seeds).
 * If the DB was created before this id was used, `resolveLessonRecord` falls back to
 * `CLIENT_LESSON_ID_TO_TITLE` + `lessons.title` match.
 */
export const CLIENT_LESSON_ID_TO_DB: Record<string, string> = {
  lesson1_1: '990e8400-e29b-41d4-a716-446655440001', // Whole Numbers
};

/** Seed lesson titles in `init-sqlite.ts` — used when alias UUID is not in DB (older databases). */
export const CLIENT_LESSON_ID_TO_TITLE: Record<string, string> = {
  lesson1_1: 'Whole Numbers',
};

export function resolveClientLessonIdToDb(lessonId: string): string {
  return CLIENT_LESSON_ID_TO_DB[lessonId] ?? lessonId;
}

export function clientLessonSeedTitle(clientLessonId: string): string | undefined {
  return CLIENT_LESSON_ID_TO_TITLE[clientLessonId];
}
