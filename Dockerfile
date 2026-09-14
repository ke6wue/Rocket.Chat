# Stage 1: Build source code using Node 22 and Yarn Berry
FROM node:22-alpine AS build-stage

# Install build dependencies required for native node modules
RUN apk add --no-cache python3 make g++ git

WORKDIR /app

# Enable Corepack to manage Yarn 4.x
RUN corepack enable

# Copy the entire codebase first so Yarn Berry workspaces resolve cleanly
COPY . .

# Run Yarn 4 install without immutable lockfile constraints
RUN yarn install --no-immutable

# Build the Meteor production bundle
RUN yarn build

# Stage 2: Production Runtime Environment
FROM node:22-alpine

RUN apk add --no-cache graphicsmagick

WORKDIR /app

# Copy the built production bundle from the build stage
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
