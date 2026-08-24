import type { RulePack } from './pack';
import type { Condition, EngineInput, Goal, WarningCode } from './types';
export interface BodyWeights {
    readonly ibw: number;
    readonly abw: number;
    readonly proteinBasisKg: number;
}
export declare function computeBodyWeights(input: EngineInput, pack: RulePack): BodyWeights;
export interface ProteinResult {
    readonly grams: number;
    readonly rate: number;
    readonly warnings: readonly WarningCode[];
}
export declare function computeProtein(input: EngineInput, targetKcal: number, weights: BodyWeights, goal: Goal, pack: RulePack): ProteinResult;
export declare function computeFat(conditions: readonly Condition[], goal: Goal, targetKcal: number, abw: number, pack: RulePack): {
    grams: number;
    pct: number;
};
export interface CarbResult {
    readonly carbG: number;
    readonly proteinG: number;
    readonly targetKcal: number;
    readonly warnings: readonly WarningCode[];
}
export declare function computeCarbs(targetKcal: number, proteinG: number, fatG: number, input: EngineInput, pack: RulePack): CarbResult;
export declare function computeFibre(targetKcal: number, pack: RulePack): number;
export declare function computeSodiumMaxMg(conditions: readonly Condition[], pack: RulePack): number;
export declare function computeAddedSugarMaxG(targetKcal: number, conditions: readonly Condition[], pack: RulePack): number;
export declare function computeSaturatedFatMaxG(targetKcal: number, conditions: readonly Condition[], pack: RulePack): number;
export declare function computeWaterMl(weightKg: number, pack: RulePack): number;
export declare const ENERGY_PER_G: {
    readonly protein: 4;
    readonly carb: 4;
    readonly fat: 9;
};
