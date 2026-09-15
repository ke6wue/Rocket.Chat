# Stage 1: Build source code using Debian-based Node 22 (glibc support for Meteor & Turbo)
FROM node:22-bookworm-slim AS builder

# Install build essential tools, python, git, curl, unzip, and ca-certificates
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    git \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Deno (required for @rocket.chat/apps execution and caching)
RUN curl -fsSL https://deno.land/x/install/install.sh | sh
ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

WORKDIR /app

# Enable Corepack for Yarn 4 / Berry
RUN corepack enable

# Install Meteor CLI inside the builder stage
RUN curl "https://install.meteor.com/" | sh
ENV PATH="${PATH}:/root/.meteor"
ENV METEOR_ALLOW_SUPERUSER=true

# Copy full repository source code
COPY . .

# Install monorepo workspace dependencies
RUN yarn install --no-immutable

# Build all monorepo packages via Turborepo
RUN yarn build

# Build the main Meteor application bundle
WORKDIR /app/apps/meteor
RUN yarn build:ci

# Standardize output path for Stage 2
RUN mkdir -p /app/bundle-out && \
    if [ -d "/app/apps/meteor/dist/bundle" ]; then \
        cp -r /app/apps/meteor/dist/bundle/* /app/bundle-out/; \
    elif [ -f "/app/apps/meteor/dist/bundle.tgz" ]; then \
        tar -xzf /app/apps/meteor/dist/bundle.tgz -C /app/bundle-out/ --strip-components=1; \
    elif [ -d "/app/apps/meteor/.meteor/local/build" ]; then \
        cp -r /app/apps/meteor/.meteor/local/build/* /app/bundle-out/; \
    fi

# Stage 2: Production Runtime Environment (Lightweight Alpine)
FROM node:22-alpine

# Install runtime dependencies (graphicsmagick and deno)
RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy the standardized bundle folder from Stage 1
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
