import '../env.js';
import initSqlJs, { Database } from 'sql.js';
import path from 'path';
import { fileURLToPath } from 'url';
import fs from 'fs';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Create database file in backend root directory
const dbPath = path.join(__dirname, '../../senyamatika.db');

console.log('📁 Database path:', dbPath);

let db: Database;
let SQL: any;

/** Apply schema-sqlite.sql so existing DB files gain new tables (idempotent IF NOT EXISTS). */
function ensureSchemaFromFile(): void {
  const coLocated = path.join(__dirname, 'schema-sqlite.sql');
  const fromSrc = path.resolve(__dirname, '../../src/db/schema-sqlite.sql');
  const schemaPath = fs.existsSync(coLocated) ? coLocated : fromSrc;
  if (!fs.existsSync(schemaPath)) {
    console.warn(
      '⚠️ schema-sqlite.sql not found; skipping auto-schema. Run: npm run db:init'
    );
    return;
  }
  const schema = fs.readFileSync(schemaPath, 'utf8');
  db.exec(schema);
  saveDatabase();
  console.log('✅ SQLite schema ensured (CREATE IF NOT EXISTS)');
}

// Initialize SQLite database
async function initDatabase() {
  SQL = await initSqlJs();
  
  // Load existing database or create new one
  if (fs.existsSync(dbPath)) {
    const buffer = fs.readFileSync(dbPath);
    db = new SQL.Database(buffer);
    console.log('✅ Existing SQLite database loaded');
  } else {
    db = new SQL.Database();
    console.log('✅ New SQLite database created');
  }

  ensureSchemaFromFile();
  return db;
}

// Save database to file
function saveDatabase() {
  if (db) {
    const data = db.export();
    const buffer = Buffer.from(data);
    fs.writeFileSync(dbPath, buffer);
  }
}

// Wrapper to match better-sqlite3 API
const dbWrapper = {
  prepare: (sql: string) => {
    return {
      run: (...params: any[]) => {
        try {
          db.run(sql, params);
          saveDatabase();
          return { changes: db.getRowsModified(), lastInsertRowid: 0 };
        } catch (error) {
          console.error('SQL Error:', error);
          console.error('SQL:', sql);
          console.error('Params:', params);
          throw error;
        }
      },
      get: (...params: any[]) => {
        try {
          const stmt = db.prepare(sql);
          stmt.bind(params);
          if (stmt.step()) {
            const row = stmt.getAsObject();
            stmt.free();
            return row;
          }
          stmt.free();
          return null;
        } catch (error) {
          console.error('SQL Error:', error);
          console.error('SQL:', sql);
          console.error('Params:', params);
          throw error;
        }
      },
      all: (...params: any[]) => {
        try {
          const stmt = db.prepare(sql);
          stmt.bind(params);
          const results: any[] = [];
          while (stmt.step()) {
            results.push(stmt.getAsObject());
          }
          stmt.free();
          return results;
        } catch (error) {
          console.error('SQL Error:', error);
          console.error('SQL:', sql);
          console.error('Params:', params);
          throw error;
        }
      }
    };
  },
  exec: (sql: string) => {
    db.exec(sql);
    saveDatabase();
  },
  pragma: (pragma: string) => {
    // sql.js doesn't support pragma, just ignore
    console.log('Pragma ignored:', pragma);
  }
};

// Initialize on import
await initDatabase();

export { dbWrapper as db, saveDatabase };
export default dbWrapper;
