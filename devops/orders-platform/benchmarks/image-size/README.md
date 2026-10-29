# Docker image size: single-stage vs multi-stage

| File | Purpose |
| --- | --- |
| `Dockerfile.single-stage` | Single-stage variant: the compiler and `libpq-dev` stay in the image, which runs as root |
| [`../../app/Dockerfile`](../../app/Dockerfile) | Multi-stage variant, used for deployments |
| `measure.sh` | Builds both images from scratch, reads their sizes with `docker image inspect`, writes `results/sizes.md` |

```bash
./measure.sh
```

## Results (GitHub Codespaces, 2026-10-28)

| Run | Single-stage, bytes | Multi-stage, bytes | Clean build | Reduction |
| --- | --- | --- | --- | --- |
| 1 ([screenshot](../../docs/screenshots/02-docker-sizes.png)) | 738,410,968 (704.2 MiB) | 207,651,171 (198.0 MiB) | 62 s / 55 s | 71.9% |
| 2 ([`results/sizes.md`](results/sizes.md)) | 738,410,763 (704.2 MiB) | 207,651,183 (198.0 MiB) | 60 s / 53 s | 71.9% |

Calculation: (738,410,763 − 207,651,183) / 738,410,763 × 100 ≈ 71.9%.
Checks: the final image contains no `gcc`, and both the app and `psycopg2` import cleanly.
The headings in `results/sizes.md` were translated into English; the values are unchanged.

![sizes](../../docs/screenshots/02-docker-sizes.png)

## Design decisions

1. **Multi-stage build:** the `build` stage installs `build-essential` and `libpq-dev` and builds wheels;
   the final stage receives only the wheels and the `libpq5` runtime library.
2. **`RUN --mount=type=bind,from=build`:** the wheels are mounted only for the install step and never
   become a layer of their own (`COPY` followed by `rm` in a later layer would not shrink the image).
3. **Layer order:** the code is copied last, so code changes do not invalidate the dependency cache.
4. **Security:** a dedicated `app` user (uid 10001), `--no-install-recommends`, and apt lists removed in the same layer.
