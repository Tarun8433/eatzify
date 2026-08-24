import type { EngineInput } from './types';
export declare class EngineInputError extends Error {
    constructor(message: string);
}
export declare function validateInput(input: EngineInput): void;
