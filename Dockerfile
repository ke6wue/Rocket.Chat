# Stage 1: Build source code using Node 22, Deno, and Yarn Berry
FROM node:22-alpine AS build-stage

# Install build tools, python, git, and Deno (required for @rocket.chat/apps)
RUN apk add --no-cache python3 make g++ git curl deno

WORKDIR /app

# Enable Corepack for Yarn Berry
RUN corepack enable

# Copy source code
COPY . .

# Run Yarn 4 install
RUN yarn install --no-immutable

# Build the Meteor production bundle
RUN yarn build

# Stage 2: Production Runtime Environment
FROM node:22-alpine

# Install runtime dependencies (graphicsmagick and deno for Apps-Engine execution)
RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

# Copy the built production bundle
COPY --from=build-stage /app/build /app

WORKDIR /app/bundle/programs/server
RUN corepack enable && yarn install --production

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000
CMD ["node", "main.js"]
