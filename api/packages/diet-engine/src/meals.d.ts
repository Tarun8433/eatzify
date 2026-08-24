import type { RulePack } from './pack';
import type { Constraints, MealTarget } from './types';
export interface DistributeArgs {
    readonly mealCount: string;
    readonly targetKcal: number;
    readonly proteinTargetG: number;
    readonly abw: number;
    readonly constraints: Constraints;
    readonly pack: RulePack;
}
export declare function distributeMeals(args: DistributeArgs): readonly MealTarget[];
export declare function isWithinTolerance(actualKcal: number, targetKcal: number, slotPct: number, pack: RulePack): boolean;
