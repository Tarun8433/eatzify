import type { RulePack } from './pack';
import type { MealTarget, Targets } from './types';
export declare const round0: (n: number) => number;
export declare const round1: (n: number) => number;
export interface RawTargets {
    readonly kcal: number;
    readonly proteinG: number;
    readonly fatG: number;
    readonly carbG: number;
    readonly fibreG: number;
    readonly sodiumMaxMg: number;
    readonly addedSugarMaxG: number;
    readonly saturatedFatMaxG: number;
    readonly waterMl: number;
}
export declare function roundTargets(raw: RawTargets): Targets;
export declare class EngineAssertionError extends Error {
    constructor(message: string);
}
export declare function assertTargetsCoherent(targets: Targets, pack: RulePack): void;
export declare function assertMealsCoherent(meals: readonly MealTarget[], targetKcal: number, pack: RulePack): void;
