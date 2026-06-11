# Build target for the docker-build smoke test, kept in a subdirectory so the
# test exercises the `context` and `dockerfile` inputs together. The COPY is
# the actual guard: marker.txt exists only under test/sub, so if the build
# context is resolved to the wrong directory (e.g. the repo root) this step
# fails — which is exactly the failure mode of mixing a root Dockerfile with a
# subdirectory context.
FROM ealen/echo-server:latest
ENV PORT=3000
COPY marker.txt ./
