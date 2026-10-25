import type { INestApplication } from '@nestjs/common';
import helmet from 'helmet';

/** Settings shared by the real server and the e2e tests. */
export function configureApp(app: INestApplication): INestApplication {
  app.use(helmet());
  const origins = (process.env.WEB_ORIGIN ?? 'http://localhost:3000,http://127.0.0.1:3000')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
  app.enableCors({ origin: origins, methods: ['GET', 'POST', 'PATCH', 'DELETE'], allowedHeaders: ['Authorization', 'Content-Type'], maxAge: 600 });
  app.enableShutdownHooks();
  return app;
}
