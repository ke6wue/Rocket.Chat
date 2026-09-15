FROM node:22-alpine AS builder

RUN apk add --no-cache python3 make g++ git curl deno

WORKDIR /app

RUN corepack enable

COPY . .

RUN yarn install --no-immutable
RUN yarn build

WORKDIR /app/apps/meteor
RUN yarn build:ci

FROM node:22-alpine

RUN apk add --no-cache graphicsmagick deno

WORKDIR /app

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
