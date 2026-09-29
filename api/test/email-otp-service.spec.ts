import { EmailOtpService } from '../src/auth/email-otp/email-otp.service';
import {
  MAX_ATTEMPTS,
  MAX_SENDS_PER_HOUR,
} from '../src/auth/email-otp/email-otp.rules';

type Row = {
  id: number;
  userId: number;
  codeHash: string;
  expiresAt: Date;
  attempts: number;
  createdAt: Date;
};

/// In-memory stand-ins: the service's job is storing, counting and emailing, so that is what's faked.
function harness(now: () => Date) {
  const rows: Row[] = [];
  const sent: string[] = [];
  let id = 0;
  const repo = {
    count: ({ where }: { where: { userId: number } }) =>
      Promise.resolve(
        rows.filter(
          (r) =>
            r.userId === where.userId &&
            r.createdAt.getTime() > now().getTime() - 3_600_000,
        ).length,
      ),
    create: (r: Omit<Row, 'id' | 'createdAt'>) => r,
    save: (r: Omit<Row, 'id' | 'createdAt'>) => {
      rows.push({ ...r, id: ++id, createdAt: now() });
      return Promise.resolve(r);
    },
    findOne: ({ where }: { where: { userId: number } }) =>
      Promise.resolve(
        [...rows]
          .filter((r) => r.userId === where.userId)
          .sort((a, b) => b.id - a.id)[0] ?? null,
      ),
    update: (rowId: number, patch: Partial<Row>) => {
      Object.assign(
        rows.find((r) => r.id === rowId)!,
        patch,
      );
      return Promise.resolve();
    },
    delete: ({ userId }: { userId: number }) => {
      for (let i = rows.length - 1; i >= 0; i--)
        if (rows[i].userId === userId) rows.splice(i, 1);
      return Promise.resolve();
    },
  };
  const mail = {
    notification: ({ data }: { data: { body: string } }) => {
      sent.push(data.body.match(/\d{6}/)![0]);
      return Promise.resolve();
    },
  };
  return {
    service: new EmailOtpService(repo as never, mail as never),
    rows,
    sent,
  };
}

describe('EmailOtpService (D-250)', () => {
  let clock = new Date('2026-09-29T10:00:00Z');
  const now = () => clock;
  beforeEach(() => (clock = new Date('2026-09-29T10:00:00Z')));

  it('should email a code that opens the account once, and never again', async () => {
    const { service, sent, rows } = harness(now);
    await service.issue(1, 'a@example.com', clock);

    expect(sent).toHaveLength(1);
    expect(rows[0].codeHash).not.toContain(sent[0]);
    expect(await service.verify(1, sent[0], clock)).toBe('ok');
    expect(await service.verify(1, sent[0], clock)).toBe('none');
  });

  it('should lock the code after MAX_ATTEMPTS wrong tries, even for the right one', async () => {
    const { service, sent } = harness(now);
    await service.issue(1, 'a@example.com', clock);
    const wrong = sent[0] === '000000' ? '000001' : '000000';

    for (let i = 0; i < MAX_ATTEMPTS; i++)
      expect(await service.verify(1, wrong, clock)).toBe('wrong');
    expect(await service.verify(1, sent[0], clock)).toBe('locked');
  });

  it('should refuse a code once it has expired', async () => {
    const { service, sent } = harness(now);
    await service.issue(1, 'a@example.com', clock);
    const later = new Date(clock.getTime() + 11 * 60_000);
    expect(await service.verify(1, sent[0], later)).toBe('expired');
  });

  it('should accept only the newest code', async () => {
    const { service, sent } = harness(now);
    await service.issue(1, 'a@example.com', clock);
    await service.issue(1, 'a@example.com', clock);
    if (sent[0] !== sent[1])
      expect(await service.verify(1, sent[0], clock)).toBe('wrong');
    expect(await service.verify(1, sent[1], clock)).toBe('ok');
  });

  it('should send at most MAX_SENDS_PER_HOUR codes an hour', async () => {
    const { service } = harness(now);
    for (let i = 0; i < MAX_SENDS_PER_HOUR; i++)
      await service.issue(1, 'a@example.com', clock);
    await expect(
      service.issue(1, 'a@example.com', clock),
    ).rejects.toMatchObject({ status: 429 });
  });
});
