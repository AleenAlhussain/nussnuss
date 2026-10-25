# NussNuss web app. Build from the repository root:
#   docker build -f apps/web/Dockerfile --build-arg NEXT_PUBLIC_API_URL=https://api.example.com .
FROM node:22-alpine AS build
WORKDIR /repo
ARG NEXT_PUBLIC_API_URL=http://localhost:4000
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL NEXT_TELEMETRY_DISABLED=1
COPY package.json package-lock.json .npmrc ./
COPY packages/core/package.json packages/core/
COPY packages/tokens/package.json packages/tokens/
COPY apps/api/package.json apps/api/
COPY apps/web/package.json apps/web/
RUN npm ci --workspace @nussnuss/web --workspace @nussnuss/core --workspace @nussnuss/tokens --include-workspace-root
COPY packages packages
COPY apps/web apps/web
RUN mkdir -p apps/mobile/lib/design \
 && npm run build -w @nussnuss/core && npm run build -w @nussnuss/tokens && npm run build -w @nussnuss/web

FROM node:22-alpine
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0 NEXT_TELEMETRY_DISABLED=1
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app
COPY --from=build /repo/apps/web/.next/standalone ./
COPY --from=build /repo/apps/web/.next/static ./apps/web/.next/static
COPY --from=build /repo/apps/web/public ./apps/web/public
USER app
EXPOSE 3000
CMD ["node", "apps/web/server.js"]
