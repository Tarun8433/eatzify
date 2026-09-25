import { DynamicModule, Module } from '@nestjs/common';
import bcrypt from 'bcryptjs';
import { DataSource } from 'typeorm';
import { CoachApplicationEntity } from '../coach/entities/coach-application.entity';
import { CoachGrantEntity } from '../coach/entities/coach-grant.entity';
import { CoachInviteEntity } from '../coach/entities/coach-invite.entity';
import { SubscriptionEntity } from '../billing/entities/subscription.entity';
import { FoodEntity } from '../foods/entities/food.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { AuditLogEntity } from './entities/audit-log.entity';
import { RoleEnum } from '../roles/roles.enum';

/**
 * Loads an ESM package from a CommonJS build.
 *
 * AdminJS 7 and every adapter it needs are `"type": "module"`; this API is `"module": "commonjs"`
 * (tsconfig) and stays that way because NestJS's decorators and the rest of the codebase depend on
 * it. TypeScript downlevels a plain `await import()` to `require()` under commonjs, which throws
 * `ERR_REQUIRE_ESM` against these packages — so the import is built through `new Function` where the
 * compiler cannot see it and cannot rewrite it.
 *
 * This is the documented bridge, not a trick of ours, and it is the single thing standing between
 * doc 20 §3's recommendation and this codebase. Recorded as D-181.
 */
const importEsm = new Function('specifier', 'return import(specifier)') as (
  specifier: string,
) => Promise<any>;

/// A session secret that is absent is a session secret that is guessed.
function requireSessionSecret(): string {
  const secret = process.env.ADMIN_SESSION_SECRET;
  if (!secret || secret.length < 32) {
    throw new Error(
      'ADMIN_SESSION_SECRET must be set to at least 32 characters before the admin panel will start.',
    );
  }
  return secret;
}

/**
 * The AdminJS panel, mounted at `/admin-panel` (docs/09 §9 owns `/api/v1/admin/*`, so the UI takes a
 * different path rather than shadowing the API it sits on top of).
 *
 * **What is deliberately read-only here.** AdminJS generates full CRUD by default, and full CRUD over
 * `users`, `coach_grant` and `audit_log` would hand an admin three things the specs forbid:
 * editing a consent grant that only the client may give (docs/10 §3), rewriting an append-only audit
 * log (docs/08 §8), and changing a role without the reason and audit row docs/10 §4 requires. Those
 * resources are listed for reading and their write actions are turned off — the audited routes in
 * `AdminController` are how they change.
 *
 * PII: `email` and `phone` are hidden from list views per docs/13 §4 ("mask by default, reveal on an
 * audited action"). AdminJS cannot write our audit row on a field reveal, so the fields are simply
 * not shown here and `GET /admin/users/{id}` remains the audited way to see them.
 */
@Module({})
export class AdminPanelModule {
  static async register(): Promise<DynamicModule> {
    const { default: AdminJS } = await importEsm('adminjs');
    const { AdminModule } = await importEsm('@adminjs/nestjs');
    const adapter = await importEsm('@adminjs/typeorm');

    AdminJS.registerAdapter({
      Database: adapter.Database,
      Resource: adapter.Resource,
    });

    /// No create, no edit, no delete. Reading is what this panel is for.
    const readOnly = {
      new: { isAccessible: false },
      edit: { isAccessible: false },
      delete: { isAccessible: false },
      bulkDelete: { isAccessible: false },
    };

    return AdminModule.createAdminAsync({
      imports: [],
      inject: [DataSource],
      useFactory: (dataSource: DataSource) => ({
        adminJsOptions: {
          rootPath: '/admin-panel',
          // All three, explicitly. AdminJS defaults these to `/admin`, `/admin/login` and
          // `/admin/logout` INDEPENDENTLY — overriding `rootPath` alone leaves the other two
          // pointing at a prefix nothing is mounted on, and the panel redirects to its own 404.
          loginPath: '/admin-panel/login',
          logoutPath: '/admin-panel/logout',
          branding: { companyName: 'Eatzify', withMadeWithLove: false },
          resources: [
            {
              resource: CoachApplicationEntity,
              options: {
                // The queue, and the two columns the whole panel exists to compare: what the
                // applicant said they are against what a human actually confirmed.
                listProperties: [
                  'userId',
                  'status',
                  'discipline',
                  'submittedAt',
                  'reviewedAt',
                  'reviewedByUserId',
                ],
                // Verify and reject go through the audited API, never through a grid cell — a
                // status changed by inline edit writes no audit row and names no reviewer.
                actions: readOnly,
              },
            },
            {
              resource: CoachInviteEntity,
              options: {
                // `phoneE164` is the invitee's number and this is a list view (docs/13 §4).
                listProperties: [
                  'coachUserId',
                  'status',
                  'scopes',
                  'expiresAt',
                  'respondedAt',
                  'createdAt',
                ],
                actions: readOnly,
              },
            },
            {
              resource: CoachGrantEntity,
              options: {
                listProperties: [
                  'clientUserId',
                  'coachUserId',
                  'scopes',
                  'status',
                  'expiresAt',
                  'endedReason',
                ],
                // docs/10 §3: only the client may grant or revoke. Not an admin, not from here.
                actions: readOnly,
              },
            },
            {
              resource: AuditLogEntity,
              options: {
                listProperties: [
                  'createdAt',
                  'actorUserId',
                  'actorRole',
                  'action',
                  'subjectUserId',
                  'resource',
                  'reason',
                ],
                // docs/08 §8 revokes UPDATE and DELETE at the database. This matches it in the UI
                // so the panel does not offer a button the database will refuse.
                actions: readOnly,
              },
            },
            {
              resource: UserEntity,
              options: {
                // No email, no phone, no name. docs/13 §4 flags exactly this list view: "full phone
                // + email visible in admin list views → mask by default, reveal on audited action".
                listProperties: ['id', 'provider', 'createdAt'],
                actions: readOnly,
              },
            },
            {
              resource: SubscriptionEntity,
              options: { actions: readOnly },
            },
            {
              // The one resource doc 20 §3 actually argued for: "the screen you'll use most and care
              // about least". Writable, because a food is content rather than a person.
              resource: FoodEntity,
              options: { actions: { delete: { isAccessible: false } } },
            },
          ],
        },
        auth: {
          /**
           * Database-backed, not a hardcoded pair. doc 20 §3's own example ships
           * `DEFAULT_ADMIN = { email, password }` in source; docs/10 §4 bans shared accounts and
           * `admin@` logins outright, so this checks a real user row and its role.
           *
           * TOTP is NOT implemented here. docs/10 §4 requires it for `super_admin`, so this panel
           * admits `admin` only until that exists — see D-181. Letting a super_admin in through a
           * password-only door would be a quieter failure than refusing them.
           */
          authenticate: async (email: string, password: string) => {
            const users = dataSource.getRepository(UserEntity);
            const user = await users.findOne({
              where: { email },
              relations: ['role'],
            });

            if (!user?.password || user.role?.id !== RoleEnum.admin) {
              return null;
            }

            const ok = await bcrypt.compare(password, user.password);

            return ok ? { email: user.email ?? '', id: String(user.id) } : null;
          },
          cookieName: 'eatzify_admin',
          cookiePassword: requireSessionSecret(),
        },
        sessionOptions: {
          resave: false,
          saveUninitialized: false,
          secret: requireSessionSecret(),
          cookie: {
            httpOnly: true,
            // An admin session cookie sent over plain HTTP is the session stolen.
            secure: process.env.NODE_ENV === 'production',
            sameSite: 'lax',
          },
        },
      }),
    });
  }
}
