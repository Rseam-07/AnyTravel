FROM node:22-bookworm-slim AS web-build
WORKDIR /app
COPY Web/package.json Web/package-lock.json ./Web/
RUN cd Web && npm ci
COPY Web ./Web
COPY Config/ServiceDefaults.json ./Config/ServiceDefaults.json
RUN cd Web && npm run build

FROM node:22-bookworm-slim AS service
ENV NODE_ENV=production HOST=0.0.0.0 PORT=8787
WORKDIR /app
COPY Backend/package.json Backend/package-lock.json ./Backend/
RUN cd Backend && npm ci --omit=dev && npm cache clean --force
COPY Backend/src ./Backend/src
COPY --from=web-build /app/Web/dist ./Web/dist
RUN mkdir -p /app/Backend/.data && chown -R node:node /app
USER node
EXPOSE 8787
HEALTHCHECK --interval=30s --timeout=8s --start-period=15s --retries=3 CMD ["node", "-e", "fetch('http://127.0.0.1:'+(process.env.PORT||8787)+'/health').then(r=>{if(!r.ok)process.exit(1)}).catch(()=>process.exit(1))"]
CMD ["node", "Backend/src/server.mjs"]
