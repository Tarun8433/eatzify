import {
  Controller,
  Get,
  Ip,
  Param,
  ParseEnumPipe,
  Query,
  Request,
  Res,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsDateString, IsIn, IsOptional } from 'class-validator';
import type { Response } from 'express';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import {
  AdminReportsService,
  REPORT_KINDS,
  toCsv,
  type Analytics,
  type Report,
  type ReportKind,
} from './admin-reports.service';
import { AuditService } from './audit.service';
import { Permit, PermissionsGuard } from './permissions.guard';

class ReportQuery {
  @IsDateString()
  from: string;

  @IsDateString()
  to: string;

  @IsOptional()
  @IsIn(['json', 'csv'])
  format?: 'json' | 'csv';
}

const KINDS = Object.fromEntries(REPORT_KINDS.map((k) => [k, k]));

/// Admin panel plan, Phase D: reports and analytics. Aggregates only; a CSV download is an
/// `export` in the audit log.
@ApiTags('Admin')
@ApiBearerAuth()
@Permit('reports.read')
@UseGuards(AuthGuard('jwt'), PermissionsGuard)
@Controller({ path: 'admin', version: '1' })
export class AdminReportsController {
  constructor(
    private readonly reports: AdminReportsService,
    private readonly audit: AuditService,
  ) {}

  @Get('analytics')
  analytics(): Promise<Analytics> {
    return this.reports.analytics();
  }

  @Get('reports/:kind')
  async report(
    @Param('kind', new ParseEnumPipe(KINDS)) kind: ReportKind,
    @Query() q: ReportQuery,
    @Request() request: { user: JwtPayloadType },
    @Ip() ip: string,
    @Res({ passthrough: true }) res: Response,
  ): Promise<Report | string> {
    const report = await this.reports.report(
      kind,
      new Date(q.from),
      new Date(q.to),
    );
    if (q.format !== 'csv') return report;

    await this.audit.record({
      actorUserId: Number(request.user.id),
      actorRole: String(request.user.role?.id ?? ''),
      action: 'export',
      resource: `report/${kind}`,
      meta: { from: report.from, to: report.to, rows: report.rows.length },
      ip,
    });
    res.set({
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': `attachment; filename="eatzify-${kind}-${report.from.slice(0, 10)}-to-${report.to.slice(0, 10)}.csv"`,
    });
    return toCsv(report);
  }
}
