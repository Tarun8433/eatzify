import { Injectable, NotFoundException } from '@nestjs/common';
import { UsersService } from '../users/users.service';
import {
  BillingService,
  type SubscriptionView,
} from '../billing/billing.service';
import { PlansService } from '../plans/plans.service';
import { User } from '../users/domain/user';

/// Enough of the active plan to decide what to SHOW; never enough to render it.
///
/// `GET /plans/current` carries the meals and their items, and this call runs on every cold start.
/// Answering "is there a plan, and what are its targets" does not need a day's food attached.
export type ActivePlanSummary = {
  id: string;
  valid_from: string;
  targets: Record<string, number> | null;
  rule_pack_version: string;
};

/// `GET /auth/me` (docs/09 §3).
export type MeView = {
  user: User;
  roles: string[];
  entitlements: SubscriptionView;
  active_plan_summary: ActivePlanSummary | null;
};

/// The one call the app makes on a cold start: who is signed in, what their tier lets them use,
/// and whether a plan already exists.
///
/// Separate from `AuthService` on purpose. That class owns credentials, sessions and token
/// rotation; this owns a read that reaches across billing and plans, and folding it in would give
/// the authentication service a reason to depend on the price matrix.
@Injectable()
export class MeService {
  constructor(
    private readonly users: UsersService,
    private readonly billing: BillingService,
    private readonly plans: PlansService,
  ) {}

  async of(userId: number): Promise<MeView> {
    const user = await this.users.findById(userId);

    // A JWT outlives the row it names — a deleted account presents a valid token until it expires.
    if (!user) throw new NotFoundException();

    // Independent reads, so they go together rather than one after the other.
    const [entitlements, plan] = await Promise.all([
      this.billing.entitlements(userId),
      this.plans.latest(userId),
    ]);

    return {
      user,
      // docs/09 says `roles`. The row carries one, and a list is the shape that survives a user
      // gaining a second one; CLAUDE.md rule 4 keeps the wire value out of the UI, not out of here.
      roles: user.role?.name ? [user.role.name] : [],
      entitlements,
      active_plan_summary: plan
        ? {
            id: plan.plan.id,
            valid_from: plan.plan.valid_from,
            targets: plan.plan.targets,
            rule_pack_version: plan.rule_pack_version,
          }
        : null,
    };
  }
}
