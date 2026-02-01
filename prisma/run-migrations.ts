import { PrismaClient } from '@prisma/client';
import * as fs from 'fs';
import * as path from 'path';

const prisma = new PrismaClient();

/**
 * Split SQL into individual statements
 * Handles functions/triggers that contain semicolons
 */
function splitSqlStatements(sql: string): string[] {
  const statements: string[] = [];
  let current = '';
  let inFunction = false;

  const lines = sql.split('\n');

  for (const line of lines) {
    const trimmedLine = line.trim();

    // Skip empty lines and comments
    if (!trimmedLine || trimmedLine.startsWith('--')) {
      continue;
    }

    // Track if we're inside a function definition
    if (trimmedLine.includes('$$')) {
      inFunction = !inFunction;
    }

    current += line + '\n';

    // If line ends with semicolon and we're not in a function, it's a complete statement
    if (trimmedLine.endsWith(';') && !inFunction) {
      const statement = current.trim();
      if (statement) {
        statements.push(statement);
      }
      current = '';
    }
  }

  // Add any remaining statement
  if (current.trim()) {
    statements.push(current.trim());
  }

  return statements;
}

async function runMigrations() {
  console.log('Starting database migrations...\n');

  const migrationsDir = path.join(__dirname, 'migrations');

  // Get all .sql files sorted by name
  const migrationFiles = fs.readdirSync(migrationsDir)
    .filter(file => file.endsWith('.sql'))
    .sort();

  if (migrationFiles.length === 0) {
    console.log('No migration files found.');
    return;
  }

  console.log(`Found ${migrationFiles.length} migration file(s):\n`);

  for (const file of migrationFiles) {
    const filePath = path.join(migrationsDir, file);
    const sql = fs.readFileSync(filePath, 'utf-8');
    const statements = splitSqlStatements(sql);

    console.log(`Running: ${file} (${statements.length} statements)`);

    let successCount = 0;
    let skipCount = 0;

    for (const statement of statements) {
      try {
        await prisma.$executeRawUnsafe(statement);
        successCount++;
      } catch (error: any) {
        // Check if it's a "already exists" error - that's OK for idempotent migrations
        if (error.message?.includes('already exists') ||
            error.message?.includes('duplicate key') ||
            error.code === '42P07' || // relation already exists
            error.code === '23505') { // unique violation
          skipCount++;
        } else {
          console.error(`  ✗ Failed at statement:\n${statement.substring(0, 100)}...`);
          console.error(`  Error: ${error.message}\n`);
          throw error;
        }
      }
    }

    console.log(`  ✓ Completed (${successCount} executed, ${skipCount} skipped)\n`);
  }

  console.log('All migrations completed successfully!');
}

runMigrations()
  .catch((error) => {
    console.error('Migration failed:', error);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });
