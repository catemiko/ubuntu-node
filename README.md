# Ubuntu 24.04 chiseled + Node.js 24 + Canonical Pebble

This repository builds and periodically refreshes a **community-maintained** minimal, multi-architecture OCI runtime image. It follows the container entrypoint and non-root conventions of Canonical's [`ubuntu/python`](https://hub.docker.com/r/ubuntu/python) rock, while providing **Node.js 24** instead of Python:

- **Ubuntu Noble 24.04** runtime libraries and CA/trust data cut from Ubuntu packages with **Chisel**.
- The Dockerfile creates `/rootfs` before `chisel cut`; Chisel requires its `--root` directory to exist.
- **Node.js 24** executable copied from the official multi-architecture `node:24-bookworm-slim` image. The Debian filesystem is not copied.
- **Canonical Pebble** as PID 1, with the `pebble enter` command interface and declarative layers for services and health checks.
- **No shell, `apt`, or `npm`** in the final runtime image, based on `scratch`.
- **Non-root `_daemon_`**, UID/GID **584792**, home `/tmp` and a sticky `1777` `/tmp`, as requested. The Dockerfile uses `USER _daemon_:_daemon_`; the kernel still runs the process as UID/GID 584792.

This is not an official Ubuntu rock or Node.js image, and is not built with Rockcraft. Its runtime and Pebble configuration follows the applicable conventions documented for `ubuntu/python`.

## GitHub Actions: build, test, sign, publish to Docker Hub

1. Create a Docker Hub repository, for example `catemiko/ubuntu-node` (choose public or private). Docker Hub repositories have a namespace and name, and should exist before publishing.
2. Create a Docker Hub **personal access token** with **Repo Read & Write** permissions. Do not use your account password. For an organization repository, an appropriate organization access token may be preferable.
3. In your **GitHub repository → Settings → Secrets and variables → Actions**, configure:

   | Type | Key | Example / value |
   | --- | --- | --- |
   | Variable | `DOCKERHUB_USERNAME` | `catemiko` (Docker Hub login identity) |
   | Variable | `DOCKERHUB_REPOSITORY` | `catemiko/ubuntu-node` (full target repository) |
   | Secret | `DOCKERHUB_TOKEN` | Docker Hub access token with push permission |

   The repository can be under a different organization namespace than the login identity; the token must have permission to push there. `DOCKERHUB_REPOSITORY` is validated before login/publishing. **Never commit the token**.
4. Commit this repository to GitHub (default branch `main`) and enable GitHub Actions.
5. Run **Actions → Build and publish Ubuntu 24.04 chiseled Node 24 to Docker Hub → Run workflow** on `main`. Pull requests and manual runs on non-`main` branches do not publish.
6. On success, pull `catemiko/ubuntu-node:24-24.04`. Check its digest in the job summary, and confirm the two-platform manifest using `docker buildx imagetools inspect`.
7. The workflow rebuilds **Mondays at 05:17 UTC** and on relevant `main` changes. Pull requests compile and test `linux/amd64` + `linux/arm64` without Docker Hub credentials.
8. The separate **Propose newer Pebble version** workflow checks new stable Pebble releases Mondays at 06:43 UTC and opens a PR to refresh pinned versions and per-architecture digests; review and merge after CI. Enable **Allow GitHub Actions to create and approve pull requests** in GitHub Actions settings for the updater. Its workflow dispatches CI explicitly for GITHUB_TOKEN-created PRs; branches other than `main` never publish.

Weekly rebuilds pick up new Ubuntu Noble package updates and the latest patch of the official floating `node:24-bookworm-slim` tag. Chisel stays pinned until explicitly updated. Pebble is pinned to a SHA256-verified release and is updated by reviewable PRs. GitHub scheduled workflow execution may be delayed or disabled in inactive public repositories.

The publish job authenticates to Docker Hub via `docker/login-action`, pushes an `amd64` + `arm64` image index using Buildx, attaches SBOM and `mode=max` provenance attestations, verifies both architectures exist, and signs the immutable digest with keyless Cosign using GitHub OIDC. Docker Hub supports these OCI artifacts. A digest, not the moving tag, is recommended for production pinning.

### Image tags

For `DOCKERHUB_REPOSITORY=catemiko/ubuntu-node`:

- `catemiko/ubuntu-node:24-24.04` — moving stable tag
- `catemiko/ubuntu-node:24-24.04-YYYYMMDD` — UTC date tag (can be overwritten by a second run that day)
- `catemiko/ubuntu-node:24-24.04-run-RUN_ID-ATTEMPT` — unique GitHub run tag

### Verify the published image

```bash
IMAGE="catemiko/ubuntu-node:24-24.04"

docker pull "${IMAGE}"
docker run --rm "${IMAGE}" exec node --version
docker buildx imagetools inspect "${IMAGE}"

# To check Node's version without Pebble's normal audit logs:
docker run --rm --entrypoint /usr/local/bin/node "${IMAGE}" --version
```

If the Docker Hub repository is private, authenticate before pulling (`docker login`). Publishing a base image to Docker Hub does **not** start a running application. Deploy applications using their own image built `FROM catemiko/ubuntu-node:24-24.04` with a Pebble service layer (next section).

## The `ubuntu/python`-style CLI

The image's entrypoint is:

```dockerfile
ENTRYPOINT ["/usr/bin/pebble", "enter"]
```

Run commands by passing them to `pebble enter`, exactly like Canonical's Python rock:

```bash
IMAGE="catemiko/ubuntu-node:24-24.04"

docker run --rm "${IMAGE}" version
# -> Pebble version

docker run --rm "${IMAGE}" plan
# -> the effective Pebble plan (empty in the generic base image)

docker run --rm "${IMAGE}" exec node --version
# -> v24.x.y

docker run --rm "${IMAGE}" exec node -e 'console.log(process.version)'
```

The base image intentionally defines **no service**. Running it without args starts Pebble but not an application. To run a long-lived app, add an application service layer as shown next.

## Bundle your own Node application as a Pebble service

Build npm dependencies in a Node builder image, then install only the application and Pebble service layer into this runtime. For example:

```dockerfile
FROM node:24-bookworm-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY server.js ./server.js

FROM catemiko/ubuntu-node:24-24.04
COPY --from=build --chown=_daemon_:_daemon_ /app /app
COPY 001-app.yaml /usr/share/pebble/layers/001-app.yaml
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
  CMD ["/usr/bin/pebble", "health"]
```

Example `001-app.yaml` (configure `/health` in your application):

```yaml
summary: Production Node service
services:
  app:
    override: replace
    summary: Node.js server
    command: /usr/local/bin/node /app/server.js
    startup: enabled
    working-dir: /app
    on-success: shutdown
    on-failure: restart
    on-check-failure:
      ready: restart
checks:
  ready:
    override: replace
    level: ready
    period: 10s
    timeout: 3s
    threshold: 3
    http:
      url: http://127.0.0.1:3000/health
```

Build and run your app (from the application folder):

```bash
docker build -t my-node-rock .
docker run --rm -d --name my-node-rock -p 3000:3000 my-node-rock

docker exec my-node-rock pebble services
docker exec my-node-rock pebble plan
docker exec my-node-rock pebble logs app
docker exec my-node-rock pebble checks
docker exec my-node-rock pebble health

docker stop my-node-rock
```

Pebble manages the Node process, restarts it according to the service configuration and runs the defined health check. The app must listen on `0.0.0.0:3000` to be reachable from outside the container; the Pebble HTTP check uses loopback inside the container.

There is **no `npm`** in the runtime; do not define Pebble service commands like `npm start` or `sh -c ...`. For packages with native `.node` addons, verify the architecture and dynamic-library compatibility; Ubuntu's Node ABI requirements and library slices must be compatible with those addons. Build each architecture separately.

## Read-only root filesystems, volumes and security

Pebble loads its configuration layers into `/var/lib/pebble/default/layers/` at startup and uses `/tmp/.pebble.socket` for its runtime control socket. `PEBBLE_PERSIST=never` prevents on-disk state persistence but does **not** remove the requirement for `$PEBBLE` to be writable. When using `--read-only`, mount a private tmpfs at `/var/lib/pebble/default` with UID/GID `584792` and mode `0700`, in addition to a writable `/tmp`. The immutable service layers live under `/usr/share/pebble/layers/`; `PEBBLE_COPY_ONCE=/usr/share/pebble` seeds those layers into the writable directory at startup. The image keeps `/var/lib/pebble/default` empty so this initial copy works even without a tmpfs mount.

```bash
docker run --rm -d --name my-node-rock \
  --read-only --cap-drop=ALL --security-opt=no-new-privileges \
  --tmpfs /tmp:rw,nosuid,nodev,size=16m,mode=1777 \
  --tmpfs /var/lib/pebble/default:rw,nosuid,nodev,size=16m,uid=584792,gid=584792,mode=0700 \
  -p 3000:3000 my-node-rock

docker exec my-node-rock pebble health
docker stop my-node-rock
```

The final image has no shell or package manager. The image's UID is non-root in both the base runtime and the app layer, including the supervising Pebble process. The Pebble API is on a Unix socket only; no unauthenticated TCP Pebble API is enabled. Do not add untrusted processes using the same runtime UID, as they may be able to access the Pebble Unix socket.

If you use Kubernetes `readOnlyRootFilesystem: true`, provide writable `emptyDir` volumes (preferably `medium: Memory`) at **both** `/tmp` and `/var/lib/pebble/default`. Kubernetes `emptyDir` mounts may default to root ownership; set `runAsUser` and `runAsGroup` to `584792` and arrange ownership/mode `0700` for Pebble (for example, using an appropriate volume-permission init container or a compatible `fsGroup`/CSI policy). Do not hide `/usr/share/pebble/layers`, since those files provide the immutable configuration. Provide any additional app-writable directories explicitly.

### What CI validates

For both `linux/amd64` and `linux/arm64`, with **read-only rootfs**, no Linux capabilities and writable tmpfs mounts at `/tmp` and `/var/lib/pebble/default`:

- `pebble enter version`, `plan` and `exec node --version` work.
- Node major `24`, expected CPU architecture, Ubuntu 24.04 and CA trust files are present.
- Pebble is PID 1, UID/GID is 584792, `/tmp` is mode `1777`, shell/apt/npm are absent.
- A mounted, real Pebble service layer starts a Node HTTP server. Pebble reports the running service, a readiness check succeeds, and the HTTP endpoint is reachable from inside the container.

The test application and Pebble layer are in `tests/pebble/`; they are test-only and **not baked into the base image**. CI mounts the test layer into the immutable seed directory and verifies that `PEBBLE_COPY_ONCE` makes it available to the running Pebble daemon.

## Software supply chain notes

- Pebble archives use per-architecture SHA256 values from the official [canonical/pebble releases](https://github.com/canonical/pebble/releases). The updater retrieves the stable release metadata and the published asset digests through the GitHub API and proposes a reviewable PR.
- Chisel tool release `v1.5.1` is pinned and validated using the upstream SHA384 file. Chisel downloads updated Ubuntu 24.04 package slices during each uncached rebuild.
- Node is updated by pulling `node:24-bookworm-slim` at rebuild time. The runtime's Ubuntu userspace is supplied by Chisel, not by Debian.
- `--pull` and `--no-cache` intentionally make CI rebuild against current upstream content. The `verify` stage and `publish` stage both rebuild, so moving upstream inputs could theoretically change between testing and publishing. For an immutable promotion pipeline, publish exactly the digests that were tested.
- SBOM/provenance and Cosign signatures do not guarantee vulnerability-free images. Add vulnerability and policy scans for your deployment, checking that scanners recognize Chisel manifests.

## References

- [Canonical ubuntu/python rock](https://hub.docker.com/r/ubuntu/python)
- [Pebble's `enter` command](https://ubuntu.com/docs/pebble/reference/cli-commands/)
- [Pebble layer specification](https://ubuntu.com/docs/pebble/reference/layer-specification/)
- [Pebble read-only filesystem and state](https://ubuntu.com/docs/pebble/how-to/manage-a-remote-system/)
- [Canonical Pebble releases](https://github.com/canonical/pebble/releases)
- [Chisel](https://ubuntu.com/chisel/docs/latest/how-to/use-chisel-in-dockerfile/)
- [GitHub Buildx publishing](https://github.com/docker/build-push-action)
- [Docker Hub publishing with GitHub Actions](https://docs.docker.com/build/ci/github-actions/)
- [Docker Hub access tokens](https://docs.docker.com/security/access-tokens/)
