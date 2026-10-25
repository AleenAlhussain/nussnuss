import { databaseUrl } from './db.module.js';
import { runMigrations } from './migrate.js';

await runMigrations(databaseUrl());
console.log('migrations applied');
