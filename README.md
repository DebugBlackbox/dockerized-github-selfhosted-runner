# Self-hosted GitHub Actions Runner

A dockerised, ephemeral GitHub Actions runner that you can scale
horizontally with a single `docker compose` command.
Builds automatically for whatever architecture your Docker host is running.

## Prerequisites

| Requirement | Notes |
|---|---|
| Docker ≥ 24 | Works on **any architecture** (amd64, arm64, etc.) |
| Docker Compose v2 | Bundled with Docker Desktop; or `sudo apt install docker-compose-plugin` |
| GitHub PAT | See [PAT permissions](#pat-permissions) below |

---

## 1 — Copy & fill in the environment file

```bash
cp .env.example .env
```

Open `.env` and set the three required variables:

```dotenv
GITHUB_OWNER=my-org          # your GitHub org or username
GITHUB_REPO=dbwrap           # repository name, or leave blank for an org-level runner
GITHUB_PAT=ghp_xxxx...       # personal access token (never commit this!)
```

> [!CAUTION]
> Never commit `.env` to version control. It is already listed in `.dockerignore`
> and should be in your root `.gitignore`.

---

## 2 — Build the image

```bash
docker compose build
```

This only needs to be run once (or whenever you change the `Dockerfile`).  
The image is tagged `dbwrap-gh-runner:latest`.

> [!TIP]
> To explicitly target a different architecture than your host, use buildx:
> ```bash
> docker buildx build --platform linux/amd64 -t dbwrap-gh-runner:latest .
> docker buildx build --platform linux/arm64 -t dbwrap-gh-runner:latest .
> ```

---

## 3 — Start runners

### Single runner

```bash
docker compose up -d
```

### Multiple runners in parallel

```bash
docker compose up --scale runner=3 -d
```

This spins up three independent containers, each registering as its own runner
in GitHub (runner-1, runner-2, runner-3 …).

---

## 4 — Check runner status

**Container logs (follow):**
```bash
docker compose logs -f
```

**Registered runners on GitHub:**  
Go to your repo → *Settings* → *Actions* → *Runners*.

---

## 5 — Stop & deregister

```bash
docker compose down
```

Each container receives `SIGTERM`, which triggers the entrypoint's cleanup
handler. The runner is automatically **deregistered** from GitHub before the
container exits — no orphaned runners left behind.

---

## 6 — Use the runners in your workflows

Change `runs-on` in any workflow job:

```yaml
jobs:
  build:
    runs-on: [self-hosted, linux]
    steps:
      - uses: actions/checkout@v4
      # …
```

Add architecture labels via `RUNNER_LABELS` in `.env` if you want to target
specific host types:

```dotenv
RUNNER_LABELS=self-hosted,linux,arm64,production
```

---

## PAT permissions

| Runner scope | Classic PAT scope | Fine-grained permission |
|---|---|---|
| Repository runner | `repo` | *Self-hosted runners* → Read & write |
| Organisation runner | `admin:org` | Org-level *Self-hosted runners* → Read & write |

> [!NOTE]
> Fine-grained PATs are preferred. Classic PATs with `repo` scope grant broad
> access — rotate them regularly and store them only in secrets.

---

## Configuration reference

All options are set via environment variables (`.env` or `docker-compose.yml`).

| Variable | Required | Default | Description |
|---|---|---|---|
| `GITHUB_OWNER` | ✅ | — | GitHub org or user name |
| `GITHUB_REPO` | ✅ | — | Repo name (*leave blank for org-level runner*) |
| `GITHUB_PAT` | ✅ | — | Personal access token |
| `RUNNER_LABELS` | | `self-hosted,linux,<arch>` | Comma-separated labels |
| `RUNNER_GROUP` | | `Default` | Runner group (Teams/Enterprise only) |
| `RUNNER_WORKDIR` | | `/tmp/_work` | Job checkout directory inside container |
| `RUNNER_NAME` | | container hostname | Displayed name in GitHub UI |

---

## How it works

```
Container starts
     │
     ▼
entrypoint.sh fetches a one-time registration token via GITHUB_PAT
     │
     ▼
./config.sh --ephemeral  ← runner registers for exactly ONE job
     │
     ▼
./run.sh  ← waits for & executes a job, then exits
     │
     ▼
Compose restarts the container → fresh runner, clean environment
```

**Ephemeral mode** means every job gets a pristine runner — no state leaks
between builds.

The Docker socket (`/var/run/docker.sock`) is mounted so runners can build and
push images without Docker-in-Docker (safer, faster).
