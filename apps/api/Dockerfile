# NussNuss API. Build from the repository root:  docker build -f apps/api/Dockerfile .
FROM node:22-alpine AS build
WORKDIR /repo
COPY package.json package-lock.json .npmrc ./
COPY packages/core/package.json packages/core/
COPY packages/tokens/package.json packages/tokens/
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
RUN npm ci --workspace @nussnuss/api --workspace @nussnuss/core --include-workspace-root
COPY packages/core packages/core
COPY apps/api apps/api
RUN npm run build -w @nussnuss/core && npm run build -w @nussnuss/api \
 && npm prune --omit=dev --workspace @nussnuss/api --workspace @nussnuss/core --include-workspace-root \
 # Replace the workspace symlinks with the built core package so the runtime image is self-contained.
 && rm -rf node_modules/@nussnuss && mkdir -p node_modules/@nussnuss \
 && mkdir node_modules/@nussnuss/core && cp -r packages/core/package.json packages/core/dist node_modules/@nussnuss/core/

FROM node:22-alpine
ENV NODE_ENV=production PORT=4000
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /repo/node_modules ./node_modules
COPY --from=build /repo/apps/api/package.json ./package.json
COPY --from=build /repo/apps/api/dist ./dist
COPY --from=build /repo/apps/api/drizzle ./drizzle
USER app
EXPOSE 4000
HEALTHCHECK --interval=15s --timeout=3s --retries=5 CMD wget -qO- http://127.0.0.1:4000/health || exit 1
CMD ["node", "dist/main.js"]
