# Stage 1: Build Meteor Bundle using Node 22, Deno, and Yarn
FROM node:22-alpine AS build-stage

# Install native build tools
RUN apk add --no-cache python3 make g++ git curl deno

WORKDIR /app

# Enable Corepack for Yarn Berry
RUN corepack enable

# Copy source repository
COPY . .

# Install workspace dependencies
RUN yarn install --no-immutable

# 1. Build all required monorepo packages
RUN yarn build

# 2. Bundle the main Meteor application into a standalone Node release
WORKDIR /app/apps/meteor
RUN yarn ddp || (npx meteor build --server-only --directory /app/bundle-out)

# Move the generated bundle to a predictable root path
RUN if [ -d "/app/apps/meteor/bundle" ]; then mv /app/apps/meteor/bundle /app/bundle-out; fi

# Stage 2: Production Runtime Environment
FROM node:22-alpine

# Install runtime binary dependencies
RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy the compiled Meteor bundle from Stage 1
COPY --from=build-stage /app/bundle-out /app

WORKDIR /app/bundle/programs/server
RUN corepack enable && yarn install --production

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000
CMD ["node", "main.js"]
