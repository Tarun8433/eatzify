import { HttpStatus, Injectable, NotFoundException } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, LessThan, Repository } from 'typeorm';
import { CoachInviteEntity } from './entities/coach-invite.entity';
import { UserEntity } from '../users/infrastructure/persistence/relational/entities/user.entity';
import { ProfileEntity } from '../profile/entities/profile.entity';
import { CoachApplicationEntity } from './entities/coach-application.entity';
import { WHAT_VERIFICATION_MEANS } from './coach-copy';
import type { GrantScope } from './entities/coach-grant.entity';
import { CoachGrantService } from './coach-grant.service';
import { CoachApplicationService } from './coach-application.service';

/// An unanswered invite is not a standing offer. Nothing in docs/09 §6 names a number, so this is
/// a product decision: long enough that a busy person is not rushed, short enough that a phone
/// number typed once does not carry a live request months later.
const INVITE_VALID_DAYS = 30;

export type InviteView = {
  id: string;
  coach_user_id: number;
  scopes: GrantScope[];
  status: string;
  expires_at: string;

  /**
   * Who is asking. Not decoration — consent that cannot name its recipient is not informed
   * consent, and "Partner #25" is what the screen showed before this existed.
   *
   * Unlike the client's side of an invite, none of this is a disclosure: a coach APPLIED to be
   * listed, accepted the partner agreement and submitted the documents behind
   * `coach_verified_attributes`. This is the professional profile they offered, shown to the one
   * person being asked to hand them health data.
   */
  coach_name: string | null;
  coach_photo_url: string | null;

  /// Self-declared. Kept separate from `coach_verified_attributes` on purpose — the gap between
  /// what somebody says they are and what a human checked has to stay visible.
  coach_discipline: string | null;

  coach_verified: boolean;

  /// What a human actually confirmed (docs/02 FR-8.3). Eatzify is not an accrediting body
  /// (doc 00 §8), so this is "we saw this document", never "this person is qualified".
  coach_verified_attributes: string[];

  /// docs/12 §6: publish exactly what verification means, wherever the badge appears.
  what_verification_means: string;
};

/**
 * One invite the CALLING coach sent, for their own Clients screen.
 *
 * `name` and `photo_url` are present only when the number belongs to an account, which means their
 * presence reveals that the number is registered — exactly what docs/09 §3 forbids the invite
 * endpoint from doing. That is a deliberate product decision taken against the spec; see
 * DECISIONS.md. Nothing else about the person is exposed, and only to the coach who already knew
 * the number well enough to type it.
 */
type CoachProfile = {
  name: string | null;
  photoUrl: string | null;
  discipline: string | null;
  verified: boolean;
  verifiedAttributes: string[];
};

export type SentInviteView = {
  id: string;
  phone_e164: string;
  scopes: GrantScope[];
  status: string;
  expires_at: string;
  created_at: string;
  name: string | null;
  photo_url: string | null;
};

/**
 * Coach invites (docs/09 §6): a coach asking one person to work with them.
 *
 * The whole class exists to keep an invite a REQUEST. It creates no access, it names scopes the
 * coach is ASKING for, and only [accept] — called by the client — turns any of it into a grant.
 */
@Injectable()
export class CoachInviteService {
  constructor(
    @InjectRepository(CoachInviteEntity)
    private readonly invites: Repository<CoachInviteEntity>,
    @InjectRepository(UserEntity)
    private readonly users: Repository<UserEntity>,
    @InjectRepository(ProfileEntity)
    private readonly profiles: Repository<ProfileEntity>,
    @InjectRepository(CoachApplicationEntity)
    private readonly applications: Repository<CoachApplicationEntity>,
    private readonly grants: CoachGrantService,
    /// Level 3's third condition lands here, so the promotion is asked for here (D-235).
    private readonly levels: CoachApplicationService,
  ) {}

  /**
   * What THIS coach has asked, for their own Clients screen — the coach's own actions read back.
   *
   * Expired rows are absent, the same rule the client's inbox follows: an invite nobody can accept
   * any more is not still pending.
   */
  async sentBy(coachUserId: number, now: Date): Promise<SentInviteView[]> {
    const rows = await this.invites.find({
      where: { coachUserId, status: 'pending' },
      order: { createdAt: 'DESC' },
    });

    const live = rows.filter((r) => r.expiresAt > now);
    if (live.length === 0) return [];

    const people = await this.peopleFor(live.map((r) => r.phoneE164));

    return live.map((r) => {
      const person = people.get(r.phoneE164);
      return {
        id: r.id,
        phone_e164: r.phoneE164,
        scopes: r.scopes,
        status: r.status,
        expires_at: r.expiresAt.toISOString(),
        created_at: r.createdAt.toISOString(),
        name: person?.name ?? null,
        photo_url: person?.photoUrl ?? null,
      };
    });
  }

  /// A phone-OTP signup never fills `user.firstName` — the name is asked for during onboarding and
  /// lands on the profile, so both are read and the user row wins when it has one.
  private async peopleFor(
    phones: string[],
  ): Promise<Map<string, { name: string | null; photoUrl: string | null }>> {
    const users = await this.users.find({ where: { phone: In(phones) } });
    if (users.length === 0) return new Map();

    const profiles = await this.profiles.find({
      where: { userId: In(users.map((u) => u.id)) },
    });
    const nameFromProfile = new Map(
      profiles.map((p) => [p.userId, p.name?.trim() ?? '']),
    );

    const out = new Map<
      string,
      { name: string | null; photoUrl: string | null }
    >();

    for (const user of users) {
      if (!user.phone) continue;
      const onUser = `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim();
      const name =
        onUser.length > 0 ? onUser : (nameFromProfile.get(user.id) ?? '');

      out.set(user.phone, {
        name: name.length > 0 ? name : null,
        photoUrl: user.photo?.path ?? null,
      });
    }

    return out;
  }

  /**
   * The coach asks. Returns nothing about the person asked.
   *
   * docs/09 §3: "never return whether a number exists." So this answers the same way whether the
   * number belongs to an account, to nobody, or to someone who has already declined — otherwise
   * the invite endpoint becomes a way to enumerate who is on the app.
   */
  async invite({
    coachUserId,
    phoneE164,
    scopes,
    now,
  }: {
    coachUserId: number;
    phoneE164: string;
    scopes: readonly GrantScope[];
    now: Date;
  }): Promise<void> {
    // The same cap the grant itself is subject to, applied at the ASK. A coach should be told
    // their level is too low when they invite, not leave the client to hit it on accept.
    await this.grants.assertScopesWithinLevel(coachUserId, scopes);

    const expiresAt = new Date(now);
    expiresAt.setDate(expiresAt.getDate() + INVITE_VALID_DAYS);

    const pending = await this.invites.findOne({
      where: { coachUserId, phoneE164, status: 'pending' },
    });

    // At most one live ask per pair. Inviting again refreshes the existing request rather than
    // stacking a second one, so a client's inbox never shows the same coach twice.
    await this.invites.save({
      ...(pending ?? {}),
      coachUserId,
      phoneE164,
      scopes: [...scopes],
      status: 'pending' as const,
      expiresAt,
      respondedAt: null,
    });
  }

  /// What this number has been asked, for the client's inbox. Expired invites are absent even
  /// before the sweep runs — the same rule grants follow.
  async pendingFor(phoneE164: string, now: Date): Promise<InviteView[]> {
    const rows = await this.invites.find({
      where: { phoneE164, status: 'pending' },
    });

    const live = rows.filter((r) => r.expiresAt > now);
    if (live.length === 0) return [];

    // Who is asking, so the person deciding can actually decide. Fetched once for the whole list
    // rather than per row.
    const coaches = await this.coachProfilesFor(live.map((r) => r.coachUserId));

    return live.map((r) => this.toView(r, coaches.get(r.coachUserId)));
  }

  /**
   * The public half of a coach's application: what they say they are, and what a human confirmed.
   *
   * Keyed by user id, not by phone — the coach is already identified on the invite row, so nothing
   * here is a lookup by number and nothing reveals whether some other number has an account.
   */
  private async coachProfilesFor(
    coachUserIds: number[],
  ): Promise<Map<number, CoachProfile>> {
    const ids = [...new Set(coachUserIds)];

    const [users, profiles, applications] = await Promise.all([
      this.users.find({ where: { id: In(ids) } }),
      this.profiles.find({ where: { userId: In(ids) } }),
      this.applications.find({ where: { userId: In(ids) } }),
    ]);

    const nameFromProfile = new Map(
      profiles.map((p) => [p.userId, p.name?.trim() ?? '']),
    );
    const byUser = new Map(applications.map((a) => [a.userId, a]));
    const out = new Map<number, CoachProfile>();

    for (const user of users) {
      const onUser = `${user.firstName ?? ''} ${user.lastName ?? ''}`.trim();
      const name =
        onUser.length > 0 ? onUser : (nameFromProfile.get(user.id) ?? '');
      const application = byUser.get(user.id);

      out.set(user.id, {
        name: name.length > 0 ? name : null,
        photoUrl: user.photo?.path ?? null,
        discipline: application?.discipline ?? null,
        verified: application?.status === 'verified',
        // Only a verified application may publish what was checked. An unreviewed applicant's
        // column is empty anyway, and reading it regardless would be one migration away from
        // leaking a claim nobody confirmed.
        verifiedAttributes:
          application?.status === 'verified'
            ? (application.verifiedAttributes ?? [])
            : [],
      });
    }

    return out;
  }

  /**
   * The client says yes. This is the only thing in the system that turns an ask into access.
   *
   * The scopes are re-checked against the coach's CURRENT level rather than trusted from the
   * invite: a coach demoted between asking and being answered must not keep the wider ask.
   */
  async accept({
    inviteId,
    clientUserId,
    clientPhoneE164,
    now,
  }: {
    inviteId: string;
    clientUserId: number;
    clientPhoneE164: string;
    now: Date;
  }): Promise<void> {
    const invite = await this.requireOwnPending(inviteId, clientPhoneE164, now);

    await this.grants.grant({
      clientUserId,
      coachUserId: invite.coachUserId,
      scopes: invite.scopes,
      now,
    });

    await this.invites.update(invite.id, {
      status: 'accepted',
      respondedAt: now,
    });

    // docs/12 §6: a client's grant is the third condition for level 3, and only a client can
    // supply it. If the coach already had the other two, this is the moment they become a
    // Coaching Partner — and the moment `chat` becomes something they can ask for (D-235).
    await this.levels.promoteToCoachingIfEligible(invite.coachUserId, now);
  }

  /// The client says no. Nothing is created, and the row stays as a record that the answer was
  /// given — a deleted invite is indistinguishable from one never sent.
  async decline({
    inviteId,
    clientPhoneE164,
    now,
  }: {
    inviteId: string;
    clientPhoneE164: string;
    now: Date;
  }): Promise<void> {
    const invite = await this.requireOwnPending(inviteId, clientPhoneE164, now);

    await this.invites.update(invite.id, {
      status: 'declined',
      respondedAt: now,
    });
  }

  /// Tidies lapsed invites out of the pending lists. Reads already ignore them.
  async expireLapsed(now: Date): Promise<number> {
    const result = await this.invites.update(
      { status: 'pending', expiresAt: LessThan(now) },
      { status: 'expired', respondedAt: now },
    );

    return result.affected ?? 0;
  }

  /**
   * The invite exists, is still open, and was addressed to THIS caller.
   *
   * A 404 for all three, deliberately: telling someone that an invite id exists but is not theirs
   * would make the id space a way to learn who has been invited by whom.
   */
  private async requireOwnPending(
    inviteId: string,
    clientPhoneE164: string,
    now: Date,
  ): Promise<CoachInviteEntity> {
    const invite = await this.invites.findOne({ where: { id: inviteId } });

    if (
      !invite ||
      invite.phoneE164 !== clientPhoneE164 ||
      invite.status !== 'pending' ||
      invite.expiresAt <= now
    ) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: {
          code: 'INVITE_NOT_FOUND',
          user_message: 'That invitation is no longer available.',
        },
      });
    }

    return invite;
  }

  private toView(row: CoachInviteEntity, coach?: CoachProfile): InviteView {
    return {
      id: row.id,
      coach_user_id: row.coachUserId,
      scopes: row.scopes,
      status: row.status,
      expires_at: row.expiresAt.toISOString(),
      coach_name: coach?.name ?? null,
      coach_photo_url: coach?.photoUrl ?? null,
      coach_discipline: coach?.discipline ?? null,
      coach_verified: coach?.verified ?? false,
      coach_verified_attributes: coach?.verifiedAttributes ?? [],
      what_verification_means: WHAT_VERIFICATION_MEANS,
    };
  }
}
