import type { RulePack } from './pack';
import type { EngineInput, Goal, WarningCode } from './types';
export declare function computeBmr(input: EngineInput, pack: RulePack): {
    bmr: number;
    reducedPrecision: boolean;
};
export declare function computeBmi(weightKg: number, heightCm: number): number;
export declare function computeTdee(bmr: number, input: EngineInput, pack: RulePack): number;
export interface GoalAdjustResult {
    readonly target: number;
    readonly appliedPct: number;
    readonly warnings: readonly WarningCode[];
}
export declare function applyGoalAdjustment(tdee: number, goal: Goal, pack: RulePack, maxDeficitPct: number): GoalAdjustResult;
