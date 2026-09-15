# Stage 1: Build source code using Debian-based Node 22
FROM node:22-bookworm-slim AS builder

ENV NODE_OPTIONS="--max-old-space-size=8192"
ENV METEOR_ALLOW_SUPERUSER=true
ENV DISABLE_OBSOLETE_VERSION_CHECK=true

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    gcc \
    git \
    curl \
    unzip \
    ca-certificates \
    pkg-config \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Deno v2.3.1
RUN curl -fsSL https://deno.land/x/install/install.sh | sh -s v2.3.1
ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

WORKDIR /app

RUN corepack enable

# Install Meteor CLI into system PATH
RUN curl "https://install.meteor.com/" | sh
ENV PATH="${PATH}:/root/.meteor"

COPY . .

# Install workspace dependencies and build packages
RUN yarn install --no-immutable || yarn install --immutable-save-lockfile
RUN yarn build

# Force Meteor to compile an uncompressed bundle directly
WORKDIR /app/apps/meteor
RUN meteor build --server-only --directory /tmp/meteor-build

# Flatten bundle contents into /app/bundle-out
RUN mkdir -p /app/bundle-out && \
    if [ -d "/tmp/meteor-build/bundle" ]; then \
        cp -r /tmp/meteor-build/bundle/* /app/bundle-out/; \
    else \
        echo "FATAL: Meteor build failed to generate output files!"; exit 1; \
    fi && \
    echo "=== VERIFYING BUILD OUTPUT ===" && \
    ls -la /app/bundle-out/main.js

# Stage 2: Production Runtime Environment
FROM node:22-alpine

RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy compiled bundle directly into /app/bundle
COPY --from=builder /app/bundle-out /app/bundle

WORKDIR /app/bundle/programs/server
RUN corepack enable && yarn install --production

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000
CMD ["node", "main.js"]
