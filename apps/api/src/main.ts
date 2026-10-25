import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module.js';
import { configureApp } from './app.js';
import { databaseUrl } from './db/db.module.js';
import { runMigrations } from './db/migrate.js';

async function bootstrap() {
  if (process.env.RUN_MIGRATIONS !== 'false') await runMigrations(databaseUrl());
  const app = configureApp(await NestFactory.create(AppModule, { bufferLogs: false }));
  const port = Number(process.env.PORT ?? 4000);
  await app.listen(port, '0.0.0.0');
  console.log(`NussNuss API on :${port}`);
}
await bootstrap();
