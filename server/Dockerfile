# Cloud Run (STG) image. The OpenAI key is not baked in; Cloud Run mounts it from Secret Manager.
FROM node:22-bookworm-slim

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY . .
RUN npm run build

ENV NODE_ENV=production
ENV HOST=0.0.0.0
ENV PORT=8080

EXPOSE 8080

CMD ["node", "dist-server/index.js"]
