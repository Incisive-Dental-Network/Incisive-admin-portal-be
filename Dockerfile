# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY prisma ./prisma/
RUN npx prisma generate

COPY tsconfig.json ./
COPY nest-cli.json ./
COPY src ./src/

RUN npm run build
RUN ls -la dist/ && ls -la dist/main.js

# Production stage
FROM node:20-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
RUN npm ci --only=production

COPY prisma ./prisma/
RUN npx prisma generate

COPY --from=builder /app/dist ./dist

RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nestjs
USER nestjs

EXPOSE 3000

CMD ["sh", "-c", "node dist/prisma/run-migrations.js && node dist/main.js"]