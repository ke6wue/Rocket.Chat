# Stage 1: Build source code using Node 22, Deno, Meteor, and Yarn Berry
FROM node:22-alpine AS builder

# Install build tools, python, git, curl, bash, and Deno
RUN apk add --no-cache python3 make g++ git curl bash deno

WORKDIR /app

# Enable Corepack for Yarn Berry
RUN corepack enable

# Install Meteor CLI inside the build container
RUN curl "https://install.meteor.com/" | sh
ENV PATH="${PATH}:/root/.meteor"
ENV METEOR_ALLOW_SUPERUSER=true

# Copy source repository
COPY . .

# Install workspace dependencies
RUN yarn install --no-immutable

# Build all monorepo packages
RUN yarn build

# Build the main Meteor application bundle
WORKDIR /app/apps/meteor
RUN yarn build:ci

# Stage 2: Production Runtime Environment
FROM node:22-alpine

# Install runtime dependencies
RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy the compiled Meteor bundle from Stage 1
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
