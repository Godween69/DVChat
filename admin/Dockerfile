# Админка DVChat: без внешних зависимостей, образ маленький
FROM node:22-alpine
WORKDIR /app
COPY package.json cli.mjs server.mjs ./
COPY lib ./lib
COPY public ./public
ENV NODE_ENV=production DVADMIN_BIND=0.0.0.0 DVADMIN_DATA_DIR=/data
VOLUME ["/data"]
USER node
EXPOSE 3101
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:3101/health || exit 1
CMD ["node", "server.mjs"]
