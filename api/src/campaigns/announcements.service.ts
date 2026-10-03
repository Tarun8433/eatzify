import {
  HttpStatus,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { IsNull, LessThanOrEqual, MoreThan, Repository } from 'typeorm';
import {
  AnnouncementEntity,
  type AnnouncementAudience,
  type AnnouncementPriority,
  type AnnouncementStatus,
} from './entities/announcement.entity';

export type AnnouncementView = {
  id: string;
  title: string;
  body: string;
  image_url: string | null;
  priority: AnnouncementPriority;
  audience: AnnouncementAudience;
  status: AnnouncementStatus;
  starts_at: string;
  ends_at: string | null;
  created_by: number;
  updated_at: string;
};

export type AnnouncementInput = {
  title: string;
  body: string;
  image_url?: string | null;
  priority: AnnouncementPriority;
  audience: AnnouncementAudience;
  starts_at?: string;
  ends_at?: string | null;
};

/// Announcements and important updates (admin panel plan, Phase C). Written in the dashboard,
/// shown on the app's home screen while published and inside their window.
@Injectable()
export class AnnouncementsService {
  constructor(
    @InjectRepository(AnnouncementEntity)
    private readonly rows: Repository<AnnouncementEntity>,
  ) {}

  /// `GET /announcements` for the app: live now, for this person's plan, most urgent first.
  async activeFor(
    paid: boolean,
    now = new Date(),
  ): Promise<AnnouncementView[]> {
    const live = {
      status: 'published' as const,
      startsAt: LessThanOrEqual(now),
    };
    const rows = await this.rows.find({
      where: [
        { ...live, endsAt: IsNull() },
        { ...live, endsAt: MoreThan(now) },
      ],
      order: { startsAt: 'DESC' },
      take: 20,
    });
    const rank = { critical: 0, important: 1, normal: 2 };
    return rows
      .filter((r) => r.audience === 'all' || (r.audience === 'paid') === paid)
      .sort((a, b) => rank[a.priority] - rank[b.priority])
      .map((r) => this.view(r));
  }

  async list(): Promise<AnnouncementView[]> {
    const rows = await this.rows.find({
      order: { createdAt: 'DESC' },
      take: 200,
    });
    return rows.map((r) => this.view(r));
  }

  async create(
    input: AnnouncementInput,
    by: number,
    now = new Date(),
  ): Promise<AnnouncementView> {
    const row = this.rows.create({
      ...this.fields(input, now),
      createdBy: by,
      status: 'draft',
    });
    return this.view(await this.rows.save(row));
  }

  async update(
    id: string,
    input: AnnouncementInput,
    now = new Date(),
  ): Promise<AnnouncementView> {
    const row = await this.find(id);
    Object.assign(row, this.fields(input, now));
    return this.view(await this.rows.save(row));
  }

  async setStatus(
    id: string,
    status: AnnouncementStatus,
  ): Promise<AnnouncementView> {
    const row = await this.find(id);
    row.status = status;
    return this.view(await this.rows.save(row));
  }

  private fields(input: AnnouncementInput, now: Date) {
    const startsAt = input.starts_at ? new Date(input.starts_at) : now;
    const endsAt = input.ends_at ? new Date(input.ends_at) : null;
    if (endsAt && endsAt.getTime() <= startsAt.getTime()) {
      throw new UnprocessableEntityException({
        status: HttpStatus.UNPROCESSABLE_ENTITY,
        error: {
          code: 'ANNOUNCEMENT_WINDOW',
          user_message: 'The end must be after the start.',
        },
      });
    }
    return {
      title: input.title.trim(),
      body: input.body.trim(),
      imageUrl: input.image_url?.trim() || null,
      priority: input.priority,
      audience: input.audience,
      startsAt,
      endsAt,
    };
  }

  private async find(id: string): Promise<AnnouncementEntity> {
    const row = await this.rows.findOne({ where: { id } });
    if (!row) {
      throw new NotFoundException({
        status: HttpStatus.NOT_FOUND,
        error: {
          code: 'ANNOUNCEMENT_NOT_FOUND',
          user_message: 'No such announcement.',
        },
      });
    }
    return row;
  }

  private view(r: AnnouncementEntity): AnnouncementView {
    return {
      id: r.id,
      title: r.title,
      body: r.body,
      image_url: r.imageUrl,
      priority: r.priority,
      audience: r.audience,
      status: r.status,
      starts_at: r.startsAt.toISOString(),
      ends_at: r.endsAt?.toISOString() ?? null,
      created_by: r.createdBy,
      updated_at: r.updatedAt.toISOString(),
    };
  }
}
