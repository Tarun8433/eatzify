"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.hashSeed = hashSeed;
exports.createPrng = createPrng;
function hashSeed(userId, planDate, packVersion) {
    const input = `${userId}|${planDate}|${packVersion}`;
    let hash = 0x811c9dc5;
    for (let i = 0; i < input.length; i += 1) {
        hash ^= input.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193);
    }
    return hash >>> 0;
}
function createPrng(seed) {
    let state = seed >>> 0;
    return function next() {
        state = (state + 0x6d2b79f5) >>> 0;
        let t = state;
        t = Math.imul(t ^ (t >>> 15), t | 1);
        t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
        return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
}
//# sourceMappingURL=prng.js.map