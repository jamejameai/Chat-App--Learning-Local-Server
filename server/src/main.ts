import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger } from '@nestjs/common';
import { json, urlencoded } from 'express';
import { AppModule } from './app.module';

async function bootstrap() {
  const logger = new Logger('Bootstrap');
  // Our own body parsers instead of Nest's default (100 KB JSON limit, which rejected every photo
  // and most voice notes with 413 "request entity too large").
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  // One line per API request (path only: query strings can carry tokens), to see what phones hit
  const http = new Logger('HTTP');
  app.use((req: any, res: any, next: () => void) => {
    const started = Date.now();
    const path = String(req.originalUrl || '').split('?')[0];
    res.on('finish', () => {
      if (!path.endsWith('/health')) {
        http.log(`${req.method} ${path} ${res.statusCode} ${Date.now() - started}ms`);
      }
    });
    next();
  });
  // Photos / voice notes arrive as base64 JSON: allow large bodies on the upload route only...
  app.use('/api/v1/attachments/upload', json({ limit: '50mb' }));
  // ...everything else stays small (profile photos are base64 too, so a few MB)
  app.use(json({ limit: '5mb' }));
  app.use(urlencoded({ extended: true, limit: '5mb' }));

  app.setGlobalPrefix('api/v1');

  // Behind Docker / the Cloudflare tunnel: trust only private-range proxies, so req.ip is the
  // real client address (needed for rate limiting) and clients cannot spoof it via X-Forwarded-For.
  app.getHttpAdapter().getInstance().set('trust proxy', 'loopback, linklocal, uniquelocal');

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Native security headers for defense-in-depth
  app.use((req: any, res: any, next: () => void) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('X-XSS-Protection', '1; mode=block');
    res.setHeader('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
    res.setHeader('Content-Security-Policy', "default-src 'none'; frame-ancestors 'none';");
    next();
  });

  app.enableCors({
    origin: '*',
    methods: 'GET,HEAD,PUT,PATCH,POST,DELETE',
    credentials: true,
  });

  const port = process.env.PORT || 3000;
  await app.listen(port, '0.0.0.0');
  logger.log(`Mini Telegram Server running on http://0.0.0.0:${port}/api/v1`);
}

bootstrap();
