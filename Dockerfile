# --- Stage 1: Dependencies ---
FROM node:18-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json ./

# TAMBAHAN: Copy prisma schema SEBELUM npm ci agar 'prisma generate' berjalan sukses
COPY prisma ./prisma 

RUN npm ci

# --- Stage 2: Builder ---
FROM node:18-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# 1. Definisikan bahwa Docker boleh menerima argumen ini dari Jenkins
ARG NEXT_PUBLIC_PUSHER_APP_KEY
ARG PUSHER_APP_ID
ARG PUSHER_SECRET

# 2. Masukkan argumen tersebut ke environment variable agar bisa dibaca Next.js saat build
ENV NEXT_PUBLIC_PUSHER_APP_KEY=$NEXT_PUBLIC_PUSHER_APP_KEY
ENV PUSHER_APP_ID=$PUSHER_APP_ID
ENV PUSHER_SECRET=$PUSHER_SECRET

# Matikan telemetry Next.js saat build
ENV NEXT_TELEMETRY_DISABLED 1

# Build project
# Jika project butuh Environment Variable saat build (seperti DATABASE_URL),
# Anda mungkin perlu menambah ARG di sini atau build via CI/CD.
RUN npm run build

# --- Stage 3: Runner (Production Image) ---
FROM node:18-alpine AS runner
WORKDIR /app

ENV NODE_ENV production
ENV NEXT_TELEMETRY_DISABLED 1

# Buat user non-root demi keamanan
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy file public (aset gambar/favicon)
COPY --from=builder /app/public ./public

# Copy folder .next/standalone (Hasil build yang sudah di-optimize)
# Folder ini otomatis dibuat karena kita set output: 'standalone' di next.config.js
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Ganti user ke non-root
USER nextjs

EXPOSE 3000
ENV PORT 3000
ENV HOSTNAME "0.0.0.0"

# Jalankan server.js (Bukan npm start, karena mode standalone menghasilkan server.js sendiri)
CMD ["node", "server.js"]
