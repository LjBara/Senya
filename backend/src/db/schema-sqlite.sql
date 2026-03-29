-- SenyamatiKard Database Schema for SQLite

-- Schools table
CREATE TABLE IF NOT EXISTS schools (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    name TEXT NOT NULL,
    address TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Teachers table
CREATE TABLE IF NOT EXISTS teachers (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    middle_name TEXT,
    suffix TEXT,
    email TEXT UNIQUE NOT NULL,
    employee_id TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female', 'nonbinary')),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Classes table
CREATE TABLE IF NOT EXISTS classes (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    school_id TEXT REFERENCES schools(id) ON DELETE CASCADE,
    grade TEXT NOT NULL,
    section TEXT NOT NULL,
    teacher_id TEXT REFERENCES teachers(id) ON DELETE SET NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(school_id, grade, section)
);

-- Students table
CREATE TABLE IF NOT EXISTS students (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    name TEXT NOT NULL,
    email TEXT UNIQUE,
    password TEXT,
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female', 'nonbinary')),
    class_id TEXT REFERENCES classes(id) ON DELETE CASCADE,
    enrollment_date TEXT NOT NULL DEFAULT (date('now')),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Index for student email lookup
CREATE INDEX IF NOT EXISTS idx_students_email ON students(email);

-- Lessons table
CREATE TABLE IF NOT EXISTS lessons (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL,
    order_num INTEGER NOT NULL,
    has_assessment INTEGER DEFAULT 0,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Subtopics table
CREATE TABLE IF NOT EXISTS subtopics (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    lesson_id TEXT REFERENCES lessons(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    order_num INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Student Progress table
CREATE TABLE IF NOT EXISTS student_progress (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    student_id TEXT REFERENCES students(id) ON DELETE CASCADE,
    lesson_id TEXT REFERENCES lessons(id) ON DELETE CASCADE,
    subtopic_id TEXT REFERENCES subtopics(id) ON DELETE CASCADE,
    completed INTEGER DEFAULT 0,
    completed_at TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(student_id, subtopic_id)
);

-- Assessments table
CREATE TABLE IF NOT EXISTS assessments (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    lesson_id TEXT REFERENCES lessons(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    max_score INTEGER NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Assessment Scores table
CREATE TABLE IF NOT EXISTS assessment_scores (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    student_id TEXT REFERENCES students(id) ON DELETE CASCADE,
    assessment_id TEXT REFERENCES assessments(id) ON DELETE CASCADE,
    score INTEGER NOT NULL,
    max_score INTEGER NOT NULL,
    completed_at TEXT DEFAULT (datetime('now')),
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now')),
    UNIQUE(student_id, assessment_id)
);

-- Engagement Logs table
CREATE TABLE IF NOT EXISTS engagement_logs (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    student_id TEXT REFERENCES students(id) ON DELETE CASCADE,
    session_date TEXT NOT NULL,
    session_duration INTEGER NOT NULL,
    lessons_accessed INTEGER DEFAULT 0,
    activity_type TEXT NOT NULL CHECK (activity_type IN ('lesson', 'assessment', 'practice')),
    created_at TEXT DEFAULT (datetime('now'))
);

-- AI-generated quizzes (debug / analytics)
CREATE TABLE IF NOT EXISTS generated_quizzes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    lesson_id TEXT,
    questions_json TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);

-- Admins table
CREATE TABLE IF NOT EXISTS admins (
    id TEXT PRIMARY KEY DEFAULT (lower(hex(randomblob(16)))),
    name TEXT NOT NULL,
    email TEXT UNIQUE NOT NULL,
    password TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    updated_at TEXT DEFAULT (datetime('now'))
);

-- Indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_students_class ON students(class_id);
CREATE INDEX IF NOT EXISTS idx_classes_teacher ON classes(teacher_id);
CREATE INDEX IF NOT EXISTS idx_classes_school ON classes(school_id);
CREATE INDEX IF NOT EXISTS idx_progress_student ON student_progress(student_id);
CREATE INDEX IF NOT EXISTS idx_progress_lesson ON student_progress(lesson_id);
CREATE INDEX IF NOT EXISTS idx_scores_student ON assessment_scores(student_id);
CREATE INDEX IF NOT EXISTS idx_scores_assessment ON assessment_scores(assessment_id);
CREATE INDEX IF NOT EXISTS idx_engagement_student ON engagement_logs(student_id);
CREATE INDEX IF NOT EXISTS idx_engagement_date ON engagement_logs(session_date);
CREATE INDEX IF NOT EXISTS idx_subtopics_lesson ON subtopics(lesson_id);

-- Triggers for updated_at
CREATE TRIGGER IF NOT EXISTS update_teachers_updated_at 
AFTER UPDATE ON teachers
BEGIN
    UPDATE teachers SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_schools_updated_at 
AFTER UPDATE ON schools
BEGIN
    UPDATE schools SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_classes_updated_at 
AFTER UPDATE ON classes
BEGIN
    UPDATE classes SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_students_updated_at 
AFTER UPDATE ON students
BEGIN
    UPDATE students SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_lessons_updated_at 
AFTER UPDATE ON lessons
BEGIN
    UPDATE lessons SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_subtopics_updated_at 
AFTER UPDATE ON subtopics
BEGIN
    UPDATE subtopics SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_progress_updated_at 
AFTER UPDATE ON student_progress
BEGIN
    UPDATE student_progress SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_assessments_updated_at 
AFTER UPDATE ON assessments
BEGIN
    UPDATE assessments SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_scores_updated_at 
AFTER UPDATE ON assessment_scores
BEGIN
    UPDATE assessment_scores SET updated_at = datetime('now') WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_admins_updated_at 
AFTER UPDATE ON admins
BEGIN
    UPDATE admins SET updated_at = datetime('now') WHERE id = NEW.id;
END;
