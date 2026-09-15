# Stage 1: Build source code using Debian-based Node 22
FROM node:22-bookworm-slim AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    make \
    g++ \
    git \
    curl \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deno.land/x/install/install.sh | sh
ENV DENO_INSTALL="/root/.deno"
ENV PATH="${DENO_INSTALL}/bin:${PATH}"

WORKDIR /app

RUN corepack enable

RUN curl "https://install.meteor.com/" | sh
ENV PATH="${PATH}:/root/.meteor"
ENV METEOR_ALLOW_SUPERUSER=true

COPY . .

RUN yarn install --no-immutable
RUN yarn build

WORKDIR /app/apps/meteor
RUN yarn build:ci

# Debug output & robust bundle extraction
RUN mkdir -p /app/bundle-out && \
    if [ -f "/app/apps/meteor/dist/bundle.tgz" ]; then \
        tar -xzf /app/apps/meteor/dist/bundle.tgz -C /app/bundle-out/ --strip-components=1; \
    elif [ -d "/app/apps/meteor/dist/bundle" ]; then \
        cp -r /app/apps/meteor/dist/bundle/* /app/bundle-out/; \
    elif [ -d "/app/apps/meteor/.meteor/local/build" ]; then \
        cp -r /app/apps/meteor/.meteor/local/build/* /app/bundle-out/; \
    fi && \
    # Fallback fix if main.js is trapped inside a nested bundle folder
    if [ ! -f "/app/bundle-out/main.js" ] && [ -d "/app/bundle-out/bundle" ]; then \
        mv /app/bundle-out/bundle/* /app/bundle-out/ && rm -rf /app/bundle-out/bundle; \
    fi && \
    ls -la /app/bundle-out

# Stage 2: Production Runtime Environment
FROM node:22-alpine

RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy the flattened bundle directory contents into /app/bundle
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
