# Stage 1: Build Meteor App from Source
FROM node:14-alpine AS build-stage
WORKDIR /app
COPY package.json yarn.lock ./
RUN yarn install --network-timeout 100000
COPY . .
RUN yarn build

# Stage 2: Production Bundle Runtime
FROM node:14-alpine
WORKDIR /app
RUN apk add --no-cache GraphicsMagick
COPY --from=build-stage /app/build /app
WORKDIR /app/bundle/programs/server
RUN yarn install --production
WORKDIR /app/bundle

ENV PORT=3000 \
    ROOT_URL=http://localhost:3000 \
    MONGO_URL=mongodb://mongodb:27017/rocketchat?replicaSet=rs0 \
    MONGO_OPLOG_URL=mongodb://mongodb:27017/local?replicaSet=rs0

EXPOSE 3000
CMD ["node", "main.js"]
