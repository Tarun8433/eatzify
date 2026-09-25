import 'dotenv/config';
import helmet from 'helmet';
import {
  ClassSerializerInterceptor,
  ValidationPipe,
  VersioningType,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory, Reflector } from '@nestjs/core';
import { DocumentBuilder, SwaggerModule } from '@nestjs/swagger';
import { useContainer } from 'class-validator';
import { AppModule } from './app.module';
import validationOptions from './utils/validation-options';
import { AllConfigType } from './config/config.type';
import { ResolvePromisesInterceptor } from './utils/serializer.interceptor';

async function bootstrap() {
  // Cashfree signs the RAW webhook bytes, and a body Nest has already parsed and re-serialised
  // has different key order and whitespace — the signature would never match again.
  const app = await NestFactory.create(AppModule, { rawBody: true });
  useContainer(app.select(AppModule), { fallbackOnErrors: true });
  const configService = app.get(ConfigService<AllConfigType>);

  app.use(
    helmet({
      contentSecurityPolicy: false,
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );

  const corsOrigins = configService.getOrThrow('app.corsOrigins', {
    infer: true,
  });
  app.enableCors({
    origin: corsOrigins.includes('*') ? '*' : corsOrigins,
  });

  // A build that fakes successful payments must not be one environment variable away from doing
  // it for real. Boot is the last point this can be caught without money having moved.
  const cashfree = configService.getOrThrow('cashfree.mode', { infer: true });
  const nodeEnv = configService.get('app.nodeEnv', { infer: true });
  if (cashfree === 'stub' && nodeEnv === 'production') {
    throw new Error(
      'CASHFREE_MODE=stub grants subscriptions without payment and cannot run in production.',
    );
  }

  /**
   * The opposite failure, and the more expensive one.
   *
   * The Client Secret is both the API credential and the key that verifies webhooks, so a gateway
   * build without a real one can take a card and can never verify the notification that says so —
   * every payment succeeds at Cashfree and activates nothing here. The customer is charged and
   * gets nothing, which is worse than being unable to charge at all.
   *
   * Refusing to boot is deliberate. A warning in a log is read after the first refund request.
   */
  if (cashfree !== 'stub') {
    const usable = (value: unknown) =>
      typeof value === 'string' &&
      value.length > 0 &&
      // A copied example file is the normal way this fails, not a missing line.
      !value.includes('REPLACE_ME');

    const appId = configService.get('cashfree.appId', { infer: true });
    const secretKey = configService.get('cashfree.secretKey', { infer: true });

    if (!usable(appId) || !usable(secretKey)) {
      throw new Error(
        `CASHFREE_MODE=${cashfree} needs a real CASHFREE_APP_ID and CASHFREE_SECRET_KEY. ` +
          'The secret key also signs webhooks, so without it every payment notification is ' +
          'refused — cards are charged and nothing is activated.',
      );
    }
  }

  app.enableShutdownHooks();
  app.setGlobalPrefix(
    configService.getOrThrow('app.apiPrefix', { infer: true }),
    {
      exclude: ['/'],
    },
  );
  app.enableVersioning({
    type: VersioningType.URI,
  });
  app.useGlobalPipes(new ValidationPipe(validationOptions));
  app.useGlobalInterceptors(
    // ResolvePromisesInterceptor is used to resolve promises in responses because class-transformer can't do it
    // https://github.com/typestack/class-transformer/issues/549
    new ResolvePromisesInterceptor(),
    new ClassSerializerInterceptor(app.get(Reflector)),
  );

  const options = new DocumentBuilder()
    .setTitle('API')
    .setDescription('API docs')
    .setVersion('1.0')
    .addBearerAuth()
    .addGlobalParameters({
      in: 'header',
      required: false,
      name: process.env.APP_HEADER_LANGUAGE || 'x-custom-lang',
      schema: {
        example: 'en',
      },
    })
    .build();

  const document = SwaggerModule.createDocument(app, options);
  SwaggerModule.setup('docs', app, document);

  await app.listen(configService.getOrThrow('app.port', { infer: true }));
}
void bootstrap();
