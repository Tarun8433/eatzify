import {
  Body,
  Controller,
  DefaultValuePipe,
  Delete,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseIntPipe,
  Patch,
  Post,
  Put,
  Query,
  Request,
  UseGuards,
} from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import type { JwtPayloadType } from '../auth/strategies/types/jwt-payload.type';
import type { RequestWithUser } from '../utils/types/request-with-user.type';
import { CreateExerciseDto, UpdateExerciseDto } from './dto/exercise.dto';
import { RoutineDto } from './dto/routine.dto';
import {
  DayOverrideDto,
  GymSettingsDto,
  ScheduleDto,
} from './dto/schedule.dto';
import { SaveWorkoutDto } from './dto/workout.dto';
import { GymLibraryService } from './gym-library.service';
import { GymPlanService } from './gym-plan.service';
import { GymStatsService } from './gym-stats.service';
import { GymWorkoutsService, HISTORY_PAGE } from './gym-workouts.service';

type Req = RequestWithUser<JwtPayloadType>;
const uid = (r: Req) => Number(r.user.id);

/// ADR-013. Every route is the signed-in person's own training — no coach or admin reads here
/// (widening that is docs/10's ask-first list). Free on every tier (D-245).
@ApiTags('Gym')
@ApiBearerAuth()
@Controller({ path: 'gym', version: '1' })
@UseGuards(AuthGuard('jwt'))
export class GymController {
  constructor(
    private readonly library: GymLibraryService,
    private readonly plan: GymPlanService,
    private readonly workouts: GymWorkoutsService,
    private readonly stats: GymStatsService,
  ) {}

  /// The hub in one call: plan, today, this week, and every routine's session ready to start offline.
  @Get()
  public overview(@Request() r: Req) {
    return this.plan.overview(uid(r));
  }

  @Get('exercises')
  public async exercises(@Request() r: Req) {
    return { exercises: await this.library.list(uid(r)) };
  }

  @Post('exercises')
  @HttpCode(HttpStatus.CREATED)
  public createExercise(@Request() r: Req, @Body() dto: CreateExerciseDto) {
    return this.library.create(uid(r), dto);
  }

  @Get('exercises/:id')
  public exercise(@Request() r: Req, @Param('id') id: string) {
    return this.stats.exerciseDetail(uid(r), id);
  }

  @Get('exercises/:id/progress')
  public progress(@Request() r: Req, @Param('id') id: string) {
    return this.stats.exerciseProgress(uid(r), id);
  }

  @Patch('exercises/:id')
  public updateExercise(
    @Request() r: Req,
    @Param('id') id: string,
    @Body() dto: UpdateExerciseDto,
  ) {
    return this.library.update(uid(r), id, dto);
  }

  @Delete('exercises/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  public removeExercise(@Request() r: Req, @Param('id') id: string) {
    return this.library.remove(uid(r), id);
  }

  @Post('routines')
  @HttpCode(HttpStatus.CREATED)
  public createRoutine(@Request() r: Req, @Body() dto: RoutineDto) {
    return this.plan.createRoutine(uid(r), dto);
  }

  @Post('routines/starter')
  @HttpCode(HttpStatus.OK)
  public starter(@Request() r: Req) {
    return this.plan.loadStarter(uid(r));
  }

  @Put('routines/:id')
  public updateRoutine(
    @Request() r: Req,
    @Param('id', ParseIntPipe) id: number,
    @Body() dto: RoutineDto,
  ) {
    return this.plan.updateRoutine(uid(r), id, dto);
  }

  @Delete('routines/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  public deleteRoutine(
    @Request() r: Req,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.plan.deleteRoutine(uid(r), id);
  }

  @Put('schedule')
  public schedule(@Request() r: Req, @Body() dto: ScheduleDto) {
    return this.plan.setSchedule(uid(r), dto.week);
  }

  @Post('schedule/day')
  @HttpCode(HttpStatus.OK)
  public day(@Request() r: Req, @Body() dto: DayOverrideDto) {
    return this.plan.setDay(uid(r), dto);
  }

  @Patch('settings')
  public settings(@Request() r: Req, @Body() dto: GymSettingsDto) {
    return this.plan.updateSettings(uid(r), dto);
  }

  /// Idempotent on the body's `id` — safe to retry after a dropped connection.
  @Post('workouts')
  @HttpCode(HttpStatus.OK)
  public save(@Request() r: Req, @Body() dto: SaveWorkoutDto) {
    return this.workouts.save(uid(r), dto);
  }

  @Get('workouts')
  public history(
    @Request() r: Req,
    @Query('before') before: string | undefined,
    @Query('limit', new DefaultValuePipe(HISTORY_PAGE), ParseIntPipe)
    limit: number,
  ) {
    return this.workouts.list(uid(r), before, limit);
  }

  @Get('workouts/:id')
  public workout(@Request() r: Req, @Param('id') id: string) {
    return this.workouts.detail(uid(r), id);
  }

  @Delete('workouts/:id')
  @HttpCode(HttpStatus.NO_CONTENT)
  public removeWorkout(@Request() r: Req, @Param('id') id: string) {
    return this.workouts.remove(uid(r), id);
  }

  @Get('calendar')
  public calendar(@Request() r: Req, @Query('month') month: string) {
    return this.stats.calendar(uid(r), month);
  }

  @Get('stats')
  public statistics(
    @Request() r: Req,
    @Query('muscle_window') muscleWindow?: string,
    @Query('effort_window') effortWindow?: string,
    @Query('hard') hard?: string,
  ) {
    return this.stats.stats(uid(r), {
      muscle_window: muscleWindow,
      effort_window: effortWindow,
      hard,
    });
  }
}
