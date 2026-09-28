import { MigrationInterface, QueryRunner } from 'typeorm';

/**
 * docs/02 §3 and docs/09 §9: support tickets, and the conversation inside one.
 *
 * Two tables rather than one: a ticket has a state and a subject, a message has an author and a
 * body, and squashing them would mean either a "first message" that is special or a status column
 * repeated on every line.
 *
 * docs/13 §6 retains these for two years from closure, which is why `closedAt` exists as its own
 * column rather than being read off the newest message.
 */
export class AddTickets1758000000000 implements MigrationInterface {
  name = 'AddTickets1758000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE "ticket" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" integer NOT NULL,
        "subject" character varying NOT NULL,
        "status" character varying NOT NULL DEFAULT 'new',
        "requestId" character varying,
        "lastMessageAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "closedAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_ticket" PRIMARY KEY ("id"),
        CONSTRAINT "CHK_ticket_status"
          CHECK ("status" IN ('new', 'open', 'waiting_user', 'resolved', 'closed')),
        CONSTRAINT "FK_ticket_user"
          FOREIGN KEY ("userId") REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_ticket_user" ON "ticket" ("userId")`,
    );
    await queryRunner.query(
      `CREATE INDEX "IDX_ticket_queue" ON "ticket" ("status", "lastMessageAt")`,
    );

    await queryRunner.query(`
      CREATE TABLE "ticket_message" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "ticketId" uuid NOT NULL,
        "senderUserId" integer NOT NULL,
        "fromSupport" boolean NOT NULL DEFAULT false,
        "body" text NOT NULL,
        "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
        CONSTRAINT "PK_ticket_message" PRIMARY KEY ("id"),
        CONSTRAINT "FK_ticket_message_ticket"
          FOREIGN KEY ("ticketId") REFERENCES "ticket"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_ticket_message_sender"
          FOREIGN KEY ("senderUserId") REFERENCES "user"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(
      `CREATE INDEX "IDX_ticket_message_thread" ON "ticket_message" ("ticketId", "createdAt")`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX "public"."IDX_ticket_message_thread"`);
    await queryRunner.query(`DROP TABLE "ticket_message"`);
    await queryRunner.query(`DROP INDEX "public"."IDX_ticket_queue"`);
    await queryRunner.query(`DROP INDEX "public"."IDX_ticket_user"`);
    await queryRunner.query(`DROP TABLE "ticket"`);
  }
}
