import { Module } from '@nestjs/common';
import { UsersModule } from './users/users.module';
import { FilesModule } from './files/files.module';
import { AuthModule } from './auth/auth.module';
import { ProfileModule } from './profile/profile.module';
import { PlansModule } from './plans/plans.module';
import { AdminModule } from './admin/admin.module';
import { AdminPanelModule } from './admin/admin-panel.module';
import { CoachModule } from './coach/coach.module';
import { PartnerModule } from './partner/partner.module';
import { MeasurementsModule } from './measurements/measurements.module';
import { FoodsModule } from './foods/foods.module';
import { LogsModule } from './logs/logs.module';
import { GymModule } from './gym/gym.module';
import { BillingModule } from './billing/billing.module';
import { NotificationsModule } from './notifications/notifications.module';
import { TicketsModule } from './tickets/tickets.module';
import { PrivacyModule } from './privacy/privacy.module';
import databaseConfig from './database/config/database.config';
import authConfig from './auth/config/auth.config';
import appConfig from './config/app.config';
import cashfreeConfig from './billing/cashfree.config';
import mailConfig from './mail/config/mail.config';
import fileConfig from './files/config/file.config';
import path from 'path';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { ScheduleModule } from '@nestjs/schedule';
import { TypeOrmModule } from '@nestjs/typeorm';
import { HeaderResolver, I18nModule } from 'nestjs-i18n';
import { TypeOrmConfigService } from './database/typeorm-config.service';
import { MailModule } from './mail/mail.module';
import { DataSource, DataSourceOptions } from 'typeorm';
import { AllConfigType } from './config/config.type';
import { SessionModule } from './session/session.module';
import { MailerModule } from './mailer/mailer.module';

// docs/20 §2 + ADR-003: Postgres only. The boilerplate's document/Mongoose branch was removed.
const infrastructureDatabaseModule = TypeOrmModule.forRootAsync({
  useClass: TypeOrmConfigService,
  dataSourceFactory: async (options?: DataSourceOptions) =>
    new DataSource(options!).initialize(),
});

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      load: [
        databaseConfig,
        authConfig,
        appConfig,
        mailConfig,
        fileConfig,
        cashfreeConfig,
      ],
      envFilePath: ['.env'],
    }),
    infrastructureDatabaseModule,
    I18nModule.forRootAsync({
      useFactory: (configService: ConfigService<AllConfigType>) => ({
        fallbackLanguage: configService.getOrThrow('app.fallbackLanguage', {
          infer: true,
        }),
        loaderOptions: { path: path.join(__dirname, '/i18n/'), watch: true },
      }),
      resolvers: [
        {
          use: HeaderResolver,
          useFactory: (configService: ConfigService<AllConfigType>) => {
            return [
              configService.get('app.headerLanguage', {
                infer: true,
              }),
            ];
          },
          inject: [ConfigService],
        },
      ],
      imports: [ConfigModule],
      inject: [ConfigService],
    }),
    UsersModule,
    FilesModule,
    AuthModule,
    ProfileModule,
    PlansModule,
    AdminModule,
    // Promise in `imports`: the panel has to load ESM-only packages before it can describe itself.
    AdminPanelModule.register(),
    CoachModule,
    PartnerModule,
    MeasurementsModule,
    FoodsModule,
    LogsModule,
    GymModule,
    BillingModule,
    SessionModule,
    MailModule,
    MailerModule,
    NotificationsModule,
    TicketsModule,
    PrivacyModule,
    // docs/11 §8's daily renewal sweep needs a clock.
    ScheduleModule.forRoot(),
  ],
})
export class AppModule {}
