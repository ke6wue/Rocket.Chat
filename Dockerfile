# ==============================================================================
# Stage 1: Build source code using Debian-based Node 22 (glibc support)
# ==============================================================================
FROM node:22-bookworm-slim AS builder

# Prevent V8 Out-Of-Memory (OOM) heap crashes during Meteor compilation
ENV NODE_OPTIONS="--max-old-space-size=8192"
ENV METEOR_ALLOW_SUPERUSER=true
ENV DISABLE_OBSOLETE_VERSION_CHECK=true

# Install build tools, python, git, curl, unzip, and C++ headers
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

# Install Deno pinned strictly to v2.3.1 (required by @rocket.chat/apps)
RUN curl -fsSL https://deno.land/x/install/install.sh | sh -s v2.3.1
ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

WORKDIR /app

# Enable Corepack for Yarn 4 / Berry
RUN corepack enable

# Install Meteor CLI
RUN curl "https://install.meteor.com/" | sh
ENV PATH="${PATH}:/root/.meteor"

# Copy source repository
COPY . .

# Install workspace dependencies and compile monorepo packages via Turborepo
RUN yarn install --no-immutable || yarn install --immutable-save-lockfile
RUN yarn build

# Build the main Meteor application bundle
WORKDIR /app/apps/meteor
RUN yarn build:ci

# Extract and flatten bundle contents directly into /app/bundle-out
RUN mkdir -p /app/bundle-out && \
    if [ -f "/app/apps/meteor/dist/bundle.tgz" ]; then \
        tar -xzf /app/apps/meteor/dist/bundle.tgz -C /app/bundle-out/ --strip-components=1; \
    elif [ -d "/app/apps/meteor/dist/bundle" ]; then \
        cp -r /app/apps/meteor/dist/bundle/* /app/bundle-out/; \
    elif [ -d "/app/apps/meteor/.meteor/local/build" ]; then \
        cp -r /app/apps/meteor/.meteor/local/build/* /app/bundle-out/; \
    fi && \
    if [ ! -f "/app/bundle-out/main.js" ] && [ -d "/app/bundle-out/bundle" ]; then \
        mv /app/bundle-out/bundle/* /app/bundle-out/ && rm -rf /app/bundle-out/bundle; \
    fi && \
    echo "=== Bundle Contents Verification ===" && \
    ls -la /app/bundle-out

# ==============================================================================
# Stage 2: Production Runtime Environment
# IMPORTANT: stays on the SAME libc family (glibc/Debian) as the builder.
# Native addons (sharp, bcrypt-style bindings, etc.) are built against glibc
# in Stage 1 and will fail to load ("Error loading shared library" / silent
# crash) on an Alpine (musl) runtime image. Do not swap this back to alpine
# unless you also rebuild all native deps against musl.
# ==============================================================================
FROM node:22-bookworm-slim

# Runtime dependencies: graphicsmagick for image processing, deno for Apps-Engine,
# fontconfig/dumb-init for stable process + signal handling in containers
RUN apt-get update && apt-get install -y --no-install-recommends \
    graphicsmagick \
    fontconfig \
    dumb-init \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Deno in the runtime image too (must match version used at build time)
RUN curl -fsSL https://deno.land/x/install/install.sh | sh -s v2.3.1
ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

WORKDIR /app

# Crucial fix: Trailing slash ensures contents are copied directly into /app/bundle
COPY --from=builder /app/bundle-out/ /app/bundle/

WORKDIR /app/bundle/programs/server
RUN corepack enable && yarn install --production

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000

# dumb-init properly forwards SIGTERM to node so `docker stop` shuts down cleanly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "main.js"]
