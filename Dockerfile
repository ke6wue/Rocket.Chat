# Stage 1: Build source using Debian-based Node 22 (full glibc support for Meteor & Turbo)
FROM node:22-bookworm-slim AS builder

# Install native build tools, python, git, curl, unzip, and ca-certificates
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

# Enable Corepack for Yarn Berry (Yarn 4)
RUN corepack enable

# Install Meteor CLI inside the builder container
RUN curl "https://install.meteor.com/" | sh
ENV PATH="${PATH}:/root/.meteor"
ENV METEOR_ALLOW_SUPERUSER=true

# Copy repository source code
COPY . .

# Install workspace dependencies
RUN yarn install --no-immutable

# Build all monorepo workspace packages via Turborepo
RUN yarn build

# Build the main Meteor application production bundle
WORKDIR /app/apps/meteor
RUN yarn build:ci

# Stage 2: Production Runtime Environment (Lightweight Alpine)
FROM node:22-alpine

# Install runtime dependencies (graphicsmagick and deno)
RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy the compiled Meteor bundle from the builder stage
COPY --from=builder /app/apps/meteor/dist/bundle /app/bundle

WORKDIR /app/bundle/programs/server
RUN corepack enable && yarn install --production

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000
CMD ["node", "main.js"]
