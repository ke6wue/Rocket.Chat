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

# Build the main Meteor application bundle.
# NOTE: apps/meteor's own build:ci script already hardcodes its own output
# path as a positional argument to `meteor build`. Passing an extra
# `--directory <path>` (via Turbo or directly) supplies a SECOND positional
# path on top of that hardcoded one, which is exactly the "too many
# arguments" error Meteor's CLI throws. So: run it bare, with no extra args,
# and let it use whatever output location the script already hardcodes.
RUN yarn build:ci

# Locate and flatten the resulting bundle into /app/bundle-out.
# Rather than guessing the exact output path (which varies by how
# build:ci is scripted), search for main.js anywhere it could plausibly
# have been written and copy its containing directory.
RUN mkdir -p /app/bundle-out && \
    BUNDLE_DIR="$(find /app -maxdepth 6 -type f -name main.js \
        -not -path '*/node_modules/*' -not -path '/app/bundle-out/*' \
        -exec dirname {} \; | head -n 1)" && \
    echo "Detected bundle directory: ${BUNDLE_DIR:-<none found>}" && \
    if [ -n "$BUNDLE_DIR" ]; then \
        cp -r "$BUNDLE_DIR"/* /app/bundle-out/; \
    else \
        TARBALL="$(find /app -maxdepth 6 -type f \( -name '*.tgz' -o -name '*.tar.gz' \) \
            -not -path '*/node_modules/*' | head -n 1)"; \
        echo "No loose main.js found; trying tarball: ${TARBALL:-<none found>}"; \
        if [ -n "$TARBALL" ]; then \
            mkdir -p /tmp/bundle-extract && \
            tar -xzf "$TARBALL" -C /tmp/bundle-extract && \
            INNER_DIR="$(find /tmp/bundle-extract -maxdepth 4 -type f -name main.js -exec dirname {} \; | head -n 1)" && \
            if [ -n "$INNER_DIR" ]; then cp -r "$INNER_DIR"/* /app/bundle-out/; fi; \
        fi; \
    fi && \
    echo "=== Bundle Contents Verification ===" && \
    ls -la /app/bundle-out && \
    if [ ! -f "/app/bundle-out/main.js" ]; then \
        echo "FATAL: main.js not found anywhere under /app after build:ci (checked loose files and tarballs)." >&2; \
        echo "Contents of apps/meteor after build:" >&2; \
        find /app/apps/meteor -maxdepth 4 2>/dev/null >&2; \
        exit 1; \
    fi

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
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Deno in the runtime image too (must match version used at build time)
RUN curl -fsSL https://deno.land/x/install/install.sh | sh -s v2.3.1
ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

WORKDIR /app

# Crucial fix: Trailing slash ensures contents are copied directly into /app/bundle
COPY --from=builder /app/bundle-out/ /app/bundle/

WORKDIR /app/bundle
# NOTE: classic (Meteor 2.x) bundles have a separate package.json/
# npm-shrinkwrap.json in programs/server requiring their own npm install.
# This bundle does NOT have one there — that's the signature of a
# Meteor 3.x bundle, where the build output already includes a complete
# node_modules and no separate install step is needed. Only run npm
# install if that file actually exists, so this Dockerfile works either way.
RUN if [ -f programs/server/package.json ]; then \
        echo "Found programs/server/package.json — installing (classic Meteor 2.x bundle layout)"; \
        cd programs/server && npm install --omit=dev; \
    else \
        echo "No programs/server/package.json — assuming Meteor 3.x bundle with node_modules already included"; \
        echo "=== Checking for node_modules in bundle ==="; \
        find /app/bundle -maxdepth 3 -type d -name node_modules; \
    fi

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000

# dumb-init properly forwards SIGTERM to node so `docker stop` shuts down cleanly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "main.js"]
