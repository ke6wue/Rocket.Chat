# Stage 1: Build source code using Node 22 and Yarn Berry
FROM node:22-alpine AS build-stage

# Install build dependencies required for native node modules
RUN apk add --no-cache python3 make g++ git

WORKDIR /app

# Enable Corepack to use the exact Yarn version specified in package.json
RUN corepack enable

# Copy package definitions and lockfile
COPY package.json yarn.lock .yarnrc.yml ./
COPY .yarn ./.yarn
COPY packages ./packages

# Install dependencies (ignoring strict engine checks)
RUN yarn install --ignore-engines || yarn install --no-immutable --ignore-engines

# Copy remaining application source
COPY . .

# Build the Meteor production bundle
RUN yarn build

# Stage 2: Production Runtime Environment
FROM node:22-alpine

RUN apk add --no-cache GraphicsMagick

WORKDIR /app

# Copy built bundle from build-stage
COPY --from=build-stage /app/build /app

WORKDIR /app/bundle/programs/server
RUN corepack enable && yarn install --production --ignore-engines

WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000
CMD ["node", "main.js"]
