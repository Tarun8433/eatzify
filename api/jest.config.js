/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  rootDir: '.',
  testMatch: ['<rootDir>/test/**/*.spec.ts'],
  moduleNameMapper: { '^@eatzify/diet-engine$': '<rootDir>/packages/diet-engine/src/index.ts' },
  collectCoverageFrom: ['src/**/*.ts'],
};
