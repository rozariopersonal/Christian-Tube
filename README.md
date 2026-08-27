# 📺 PrivateTube - Multi-Instance White-Label Platform

**PrivateTube** is a high-performance, white-label, config-driven video streaming and AI transcription platform. The repository is structured as an **Nx Monorepo** designed to deploy multiple distinct, fully-isolated Tube instances (**ChristianTube**, **Centum Academy**, etc.) from a single core codebase.

---

## 🏗️ Monorepo Architecture

```
PrivateTube/
├── apps/
│   ├── mobile/                     # 📱 Flutter Mobile Client (Multi-brand, themeable)
│   │   ├── android/
│   │   ├── lib/
│   │   └── pubspec.yaml
│   │
│   └── backend/                    # 🚀 NestJS + Prisma Engine (PostgreSQL, Gemini AI, R2)
│       ├── prisma/
│       │   └── schema.prisma
│       ├── src/
│       │   ├── modules/
│       │   │   ├── videos/         # Video catalog & live streams
│       │   │   ├── channels/       # Monitored channel curation
│       │   │   ├── youtube/        # YouTube Data API sync cron jobs
│       │   │   ├── transcription/  # Gemini AI speech-to-text pipeline
│       │   │   └── storage/        # Cloudflare R2 object storage
│       │   └── main.ts
│       └── package.json
│
├── instances/                      # 🎯 Instance Profiles & Assets
│   ├── christian_tube/             # ChristianTube (org.rozario.christiantube.mobile)
│   │   ├── config.json
│   │   ├── seed_channels.json
│   │   └── assets/icon.png
│   │
│   ├── centum_academy/             # Centum Academy (org.centumacademy.mobile)
│   │   ├── config.json
│   │   ├── seed_channels.json
│   │   └── assets/icon.png
│   │
│   └── template/                   # ⚡ 1-Click Generator for ANY new Tube
│
├── scripts/
│   ├── prepare-instance.js         # Build script for asset overlays & config injection
│   └── prepare-instance.ps1
│
├── deployment/
│   └── prod/
│       └── Dockerfile.backend      # Multi-stage Docker build for Render
│
└── .github/
    └── workflows/
        └── release.yml             # Parallel Matrix CI/CD for all instances
```

---

## 🚀 Active Instances

| Instance | Application ID | Theme | Target Release Repository |
| :--- | :--- | :--- | :--- |
| **ChristianTube** | `org.rozario.christiantube.mobile` | Blue & Gold | [Christian-Tube-Releases](https://github.com/rozariopersonal/Christian-Tube-Releases) |
| **Centum Academy** | `org.centumacademy.mobile` | Emerald & Tech | [Centum-Academy-Releases](https://github.com/rozariopersonal/Centum-Academy-Releases) |

---

## 🛠️ Local Development

### 1. Prepare an Instance for Mobile Build
To switch the mobile app to a specific instance:
```bash
# For ChristianTube
node scripts/prepare-instance.js christian_tube

# For Centum Academy
node scripts/prepare-instance.js centum_academy
```

### 2. Run the Mobile App
```bash
cd apps/mobile
flutter run
```

### 3. Run the Backend Service
```bash
cd apps/backend
pnpm install
npx prisma generate
INSTANCE_ID=christian_tube pnpm start:dev
```

---

## 🤖 Automated CI/CD Releases

Every release tag push (e.g. `v1.28.0`) automatically runs a **parallel GitHub Actions Matrix**:
1. **Job 1**: Prepares & builds `ChristianTube` $\rightarrow$ publishes release `v1.28.0` with `christian-tube.apk` & QR code to `Christian-Tube-Releases`.
2. **Job 2**: Prepares & builds `Centum Academy` $\rightarrow$ publishes release `v1.28.0` with `centum-academy.apk` & QR code to `Centum-Academy-Releases`.

---

## 🐳 Backend Deployment on Render

Use `deployment/prod/Dockerfile.backend` on Render:
* **Christian Tube Service**: Set Environment Variable `INSTANCE_ID=christian_tube`.
* **Centum Academy Service**: Set Environment Variable `INSTANCE_ID=centum_academy`.
