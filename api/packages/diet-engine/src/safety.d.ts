import type { RulePack } from './pack';
import type { EngineInput, Gate, Goal, WarningCode } from './types';
export interface GateResult {
    readonly gates: readonly Gate[];
    readonly warnings: readonly WarningCode[];
}
export declare function evaluateGates(input: EngineInput, bmi: number, pack: RulePack): GateResult;
export declare function maxDeficitPct(input: EngineInput, pack: RulePack): {
    pct: number;
    warnings: readonly WarningCode[];
};
export interface EffectiveGoalResult {
    readonly goal: Goal;
    readonly warnings: readonly WarningCode[];
}
export declare function effectiveGoal(input: EngineInput, bmi: number, pack: RulePack): EffectiveGoalResult;
export interface ClampResult {
    readonly target: number;
    readonly applied: boolean;
    readonly warnings: readonly WarningCode[];
}
export declare function clampTarget(rawTarget: number, bmr: number, tdee: number, input: EngineInput, pack: RulePack): ClampResult;
