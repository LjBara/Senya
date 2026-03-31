import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcrypt';
import { CLIENT_LESSON_ID_TO_DB } from '../config/lessonAliases.js';
import db from './connection.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Read and execute schema
const schemaPath = path.join(__dirname, 'schema-sqlite.sql');
const schema = fs.readFileSync(schemaPath, 'utf8');

console.log('📋 Creating database schema...');
db.exec(schema);
console.log('✅ Schema created successfully');

// Helper function to generate UUID-like IDs
function generateId(): string {
  return Array.from({ length: 32 }, () => 
    Math.floor(Math.random() * 16).toString(16)
  ).join('');
}

// Seed data
console.log('🌱 Seeding database...');

// Insert admin
const adminPassword = await bcrypt.hash('admin123', 10);
const adminId = generateId();
db.prepare(`
  INSERT INTO admins (id, name, email, password)
  VALUES (?, ?, ?, ?)
`).run(adminId, 'System Administrator', 'admin@senyamatika.com', adminPassword);
console.log('✅ Admin created: admin@senyamatika.com / admin123');

// Insert schools
const school1Id = generateId();
const school2Id = generateId();
db.prepare(`
  INSERT INTO schools (id, name, address)
  VALUES (?, ?, ?)
`).run(school1Id, 'Manila Elementary School', '123 Rizal Avenue, Manila');

db.prepare(`
  INSERT INTO schools (id, name, address)
  VALUES (?, ?, ?)
`).run(school2Id, 'Quezon City High School', '456 Commonwealth Ave, Quezon City');
console.log('✅ Schools created');

// Insert teachers
const teacher1Id = generateId();
const teacher2Id = generateId();
const teacher1Password = await bcrypt.hash('cruz_001', 10);
const teacher2Password = await bcrypt.hash('santos_002', 10);

db.prepare(`
  INSERT INTO teachers (id, first_name, last_name, middle_name, email, employee_id, password, gender)
  VALUES (?, ?, ?, ?, ?, ?, ?, ?)
`).run(teacher1Id, 'Maria', 'Cruz', 'Santos', 'maria.cruz@school.com', 'EMP-001', teacher1Password, 'female');

db.prepare(`
  INSERT INTO teachers (id, first_name, last_name, email, employee_id, password, gender)
  VALUES (?, ?, ?, ?, ?, ?, ?)
`).run(teacher2Id, 'Juan', 'Santos', 'juan.santos@school.com', 'EMP-002', teacher2Password, 'male');
console.log('✅ Teachers created');
console.log('   - maria.cruz@school.com (EMP-001 / cruz_001)');
console.log('   - juan.santos@school.com (EMP-002 / santos_002)');

// Insert classes
const class1Id = generateId();
const class2Id = generateId();
const class3Id = generateId();

db.prepare(`
  INSERT INTO classes (id, school_id, grade, section, teacher_id)
  VALUES (?, ?, ?, ?, ?)
`).run(class1Id, school1Id, 'Grade 1', 'Section A', teacher1Id);

db.prepare(`
  INSERT INTO classes (id, school_id, grade, section, teacher_id)
  VALUES (?, ?, ?, ?, ?)
`).run(class2Id, school1Id, 'Grade 1', 'Section B', teacher1Id);

db.prepare(`
  INSERT INTO classes (id, school_id, grade, section, teacher_id)
  VALUES (?, ?, ?, ?, ?)
`).run(class3Id, school2Id, 'Grade 2', 'Section A', teacher2Id);
console.log('✅ Classes created');

// Insert students
const studentIds: string[] = [];
const studentNames = [
  'Juan Dela Cruz', 'Maria Santos', 'Pedro Garcia', 'Ana Reyes', 'Carlos Lopez',
  'Sofia Martinez', 'Miguel Torres', 'Isabel Gonzales', 'Diego Fernandez', 'Carmen Ramirez',
  'Luis Hernandez', 'Rosa Flores', 'Antonio Morales', 'Elena Jimenez', 'Francisco Ruiz'
];

studentNames.forEach((name, index) => {
  const studentId = generateId();
  studentIds.push(studentId);
  const classId = index < 5 ? class1Id : index < 10 ? class2Id : class3Id;
  const gender = index % 2 === 0 ? 'male' : 'female';
  
  db.prepare(`
    INSERT INTO students (id, name, gender, class_id)
    VALUES (?, ?, ?, ?)
  `).run(studentId, name, gender, classId);
});
console.log(`✅ ${studentNames.length} students created`);

// Insert lessons
const lessons = [
  { title: 'Whole Numbers', description: 'Understanding whole numbers and their properties', category: 'Number Values', order: 1, hasAssessment: 1 },
  { title: 'Place Value', description: 'Learning about ones, tens, hundreds', category: 'Number Values', order: 2, hasAssessment: 1 },
  { title: 'Addition', description: 'Basic addition operations', category: 'Operations', order: 3, hasAssessment: 1 },
  { title: 'Subtraction', description: 'Basic subtraction operations', category: 'Operations', order: 4, hasAssessment: 1 },
  { title: 'Multiplication', description: 'Introduction to multiplication', category: 'Operations', order: 5, hasAssessment: 1 },
  { title: 'Division', description: 'Introduction to division', category: 'Operations', order: 6, hasAssessment: 1 },
  { title: 'Fractions', description: 'Understanding fractions', category: 'Fractions', order: 7, hasAssessment: 1 },
  { title: 'Decimals', description: 'Introduction to decimal numbers', category: 'Decimals', order: 8, hasAssessment: 1 },
  { title: 'Money Value', description: 'Understanding money and its value', category: 'Mensuration', order: 9, hasAssessment: 1 },
  { title: 'Time', description: 'Reading and understanding time', category: 'Mensuration', order: 10, hasAssessment: 1 }
];

const lessonIds: string[] = [];
lessons.forEach((lesson, index) => {
  const stableId =
    index === 0 && lesson.title === 'Whole Numbers' ? CLIENT_LESSON_ID_TO_DB['lesson1_1'] : undefined;
  const lessonId = stableId ?? generateId();
  lessonIds.push(lessonId);
  
  db.prepare(`
    INSERT INTO lessons (id, title, description, category, order_num, has_assessment)
    VALUES (?, ?, ?, ?, ?, ?)
  `).run(lessonId, lesson.title, lesson.description, lesson.category, lesson.order, lesson.hasAssessment);
});
console.log(`✅ ${lessons.length} lessons created`);

// Insert subtopics
lessonIds.forEach((lessonId, lessonIndex) => {
  for (let i = 1; i <= 3; i++) {
    const subtopicId = generateId();
    db.prepare(`
      INSERT INTO subtopics (id, lesson_id, title, order_num)
      VALUES (?, ?, ?, ?)
    `).run(subtopicId, lessonId, `${lessons[lessonIndex].title} - Part ${i}`, i);
  }
});
console.log('✅ Subtopics created');

// Insert assessments
lessonIds.forEach((lessonId, index) => {
  const assessmentId = generateId();
  db.prepare(`
    INSERT INTO assessments (id, lesson_id, title, max_score)
    VALUES (?, ?, ?, ?)
  `).run(assessmentId, lessonId, `${lessons[index].title} Assessment`, 100);
});
console.log('✅ Assessments created');

// Insert some sample progress
studentIds.slice(0, 5).forEach(studentId => {
  lessonIds.slice(0, 3).forEach(lessonId => {
    const subtopics = db.prepare('SELECT id FROM subtopics WHERE lesson_id = ?').all(lessonId);
    subtopics.forEach((subtopic: any) => {
      const progressId = generateId();
      db.prepare(`
        INSERT INTO student_progress (id, student_id, lesson_id, subtopic_id, completed, completed_at)
        VALUES (?, ?, ?, ?, ?, datetime('now'))
      `).run(progressId, studentId, lessonId, subtopic.id, 1);
    });
  });
});
console.log('✅ Sample progress data created');

// Insert some sample assessment scores
studentIds.slice(0, 5).forEach(studentId => {
  const assessments = db.prepare('SELECT id FROM assessments LIMIT 3').all();
  assessments.forEach((assessment: any) => {
    const scoreId = generateId();
    const score = Math.floor(Math.random() * 30) + 70; // Random score between 70-100
    db.prepare(`
      INSERT INTO assessment_scores (id, student_id, assessment_id, score, max_score)
      VALUES (?, ?, ?, ?, ?)
    `).run(scoreId, studentId, assessment.id, score, 100);
  });
});
console.log('✅ Sample assessment scores created');

// Insert some engagement logs
studentIds.slice(0, 5).forEach(studentId => {
  for (let i = 0; i < 3; i++) {
    const logId = generateId();
    const duration = Math.floor(Math.random() * 30) + 10; // 10-40 minutes
    const activityTypes = ['lesson', 'assessment', 'practice'];
    const activityType = activityTypes[Math.floor(Math.random() * activityTypes.length)];
    
    db.prepare(`
      INSERT INTO engagement_logs (id, student_id, session_date, session_duration, lessons_accessed, activity_type)
      VALUES (?, ?, date('now'), ?, ?, ?)
    `).run(logId, studentId, duration, Math.floor(Math.random() * 3) + 1, activityType);
  }
});
console.log('✅ Sample engagement logs created');

console.log('\n🎉 Database initialization complete!');
console.log('\n📝 Login Credentials:');
console.log('   Admin: admin@senyamatika.com / admin123');
console.log('   Teacher 1: EMP-001 / cruz_001');
console.log('   Teacher 2: EMP-002 / santos_002');

process.exit(0);
