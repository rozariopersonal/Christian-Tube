import { NestFactory } from '@nestjs/core';
import { Logger, ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { AppModule } from './app.module';

async function bootstrap() {
  const logger = new Logger('PrivateTubeBootstrap');
  const app = await NestFactory.create(AppModule);

  const configService = app.get(ConfigService);
  const appName = configService.get<string>('appName') || 'PrivateTube';
  const port = configService.get<number>('port') || 3000;

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
