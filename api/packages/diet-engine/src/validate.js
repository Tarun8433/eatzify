"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.EngineInputError = void 0;
exports.validateInput = validateInput;
class EngineInputError extends Error {
    constructor(message) {
        super(message);
        this.name = 'EngineInputError';
    }
}
exports.EngineInputError = EngineInputError;
const RANGES = {
    ageYears: [18, 99],
    heightCm: [120, 220],
    weightKg: [30, 250],
};
function validateInput(input) {
    for (const [field, [min, max]] of Object.entries(RANGES)) {
        const value = input[field];
        if (!Number.isFinite(value) || value < min || value > max) {
            throw new EngineInputError(`${field} out of range: ${value} (expected ${min}..${max})`);
        }
    }
    if (input.conditions.length === 0) {
        throw new EngineInputError('conditions must contain at least "none"');
    }
    if (input.conditions.includes('none') && input.conditions.length > 1) {
        throw new EngineInputError('condition "none" is exclusive and cannot appear with others');
    }
    if (input.planDate.match(/^\d{4}-\d{2}-\d{2}$/) === null) {
        throw new EngineInputError(`planDate must be YYYY-MM-DD, got "${input.planDate}"`);
    }
}
//# sourceMappingURL=validate.js.map