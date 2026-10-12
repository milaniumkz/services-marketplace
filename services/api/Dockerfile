FROM node:24-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20 AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY services/api/package.json services/api/package.json
COPY apps/admin/package.json apps/admin/package.json
COPY apps/client/package.json apps/client/package.json
COPY apps/web/package.json apps/web/package.json
COPY packages/contracts/package.json packages/contracts/package.json
RUN --mount=type=secret,id=npm-ca \
    if [ -f /run/secrets/npm-ca ]; then export NODE_EXTRA_CA_CERTS=/run/secrets/npm-ca; fi; npm ci
COPY services/api services/api
RUN npm run build --workspace @marketplace/api

FROM node:24-bookworm-slim@sha256:d6aa754f16b3197301076f047b5def2f02ea1dbbc2ca920407d46d7ec7f87b20
WORKDIR /app
ENV NODE_ENV=production API_HOST=0.0.0.0 API_PORT=3000
COPY --from=build --chown=node:node /app/node_modules /app/node_modules
COPY --from=build --chown=node:node /app/services/api /app/services/api
RUN mkdir -p /app/.local && chown node:node /app/.local
USER node
EXPOSE 3000
CMD ["node", "services/api/dist/main.js"]
