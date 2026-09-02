/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  // TypeScript FIRST. ts-jest's default order puts 'js' ahead of 'ts', and `src/` still holds a set
  // of compiled `.js` files from an old build that were committed by mistake — so every
  // `import from '../src/x'` in these tests resolved to the stale August build, not to the source
  // next to it. The suite was green against code nobody was editing. Delete `src/*.{js,d.ts,map}`
  // and this line stops mattering; until then it is what makes the tests test the source.
  moduleFileExtensions: ['ts', 'tsx', 'js', 'mjs', 'cjs', 'json', 'node'],
  testMatch: ['<rootDir>/test/**/*.spec.ts'],
  collectCoverageFrom: ['src/**/*.ts'],
  // docs/16 §1: engine floor is 95 %
  coverageThreshold: {
    global: { statements: 95, branches: 90, functions: 95, lines: 95 },
  },
};
