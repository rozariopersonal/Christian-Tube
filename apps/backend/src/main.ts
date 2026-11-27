import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { text } from 'express';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { AppModule } from './app.module';

async function bootstrap() {
  const logger = new Logger('ChristianAppBootstrap');
  const app = await NestFactory.create(AppModule);

  const configService = app.get(ConfigService);
  const appName = configService.get<string>('appName') || 'ChristianApp';
  const port = configService.get<number>('port') || 3000;

  // XML Body Parser for Google WebSub Push Notifications
  app.use(text({ type: ['application/xml', 'text/xml', 'application/atom+xml'] }));

  // Security Middleware
  app.use(helmet());
  app.enableCors({
    origin: true,
    credentials: true,
  });

  // Global Rate Limiting
  app.use(
    rateLimit({
      windowMs: 60 * 1000, // 1 minute
      max: 100, // limit each IP to 100 requests per windowMs
    }),
  );

  // Tighter rate limits for channel requests & YouTube search (quota protection)
  app.use(
    ['/channels/request', '/api/channels/request'],
    rateLimit({
      windowMs: 60 * 1000,
      max: 15,
      message: { message: 'Too many channel requests. Please try again in a minute.' },
    }),
  );
  app.use(
    ['/channels/search-youtube', '/api/channels/search-youtube'],
    rateLimit({
      windowMs: 60 * 1000,
      max: 30,
      message: { message: 'Too many YouTube search requests. Please slow down.' },
    }),
  );

  // Global Validation
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      transform: true,
    }),
  );

  await app.listen(port, '0.0.0.0');
  logger.log(`🚀 ${appName} Backend Engine running on http://0.0.0.0:${port}`);
}
bootstrap();
