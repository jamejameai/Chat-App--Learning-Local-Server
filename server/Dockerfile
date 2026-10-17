# ============================================================================
# Multi-stage Production Dockerfile for Mini Telegram Server
# ============================================================================

# Stage 1: Build Application
FROM node:24-alpine AS builder

WORKDIR /app

# Install dependencies (cached if package files don't change)
COPY package*.json ./
RUN npm ci

# Copy source code and build production bundle
COPY . .
RUN npm run build

# Stage 2: Production Runtime
FROM node:24-alpine AS runner

WORKDIR /app

ENV NODE_ENV=production

# Install tini for proper PID 1 signal forwarding and child process reaping
RUN apk add --no-cache tini curl

# Copy production dependency manifest and install production-only dependencies
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy compiled artifacts and database migration scripts from builder
COPY --from=builder --chown=node:node /app/dist ./dist
COPY --from=builder --chown=node:node /app/src/database/migrations ./dist/database/migrations

# Create uploads storage directory with appropriate non-root permissions
RUN mkdir -p /uploads && chown -R node:node /app /uploads

# Run as non-root user for principle of least privilege
USER node

# Health check against local health endpoint
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://127.0.0.1:3000/api/v1/health || exit 1

EXPOSE 3000

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/main.js"]
