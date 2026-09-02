# Production image (D-159). The boilerplate's dev Dockerfile referenced wait-for-it.sh and
# startup.relational.dev.sh, which never existed in this repo — it had never actually been built.
# This one builds the compiled server; readiness ordering lives in docker-compose.yaml
# (postgres healthcheck + depends_on), not in a wrapper script.
FROM node:24.14.1-alpine

WORKDIR /usr/src/app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

# Migrations run on every boot — idempotent, and what keeps a deploy from racing its schema.
# Seeds are a deliberate one-time step, never automatic: npm run seed:run:relational.
CMD ["sh", "-c", "npm run migration:run && node dist/main"]
