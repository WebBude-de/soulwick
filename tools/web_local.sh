#!/usr/bin/env bash
# Serves the browser version of the game on http://localhost:3110 against the local platform
# (SOULWICK_ENV=local, docs/WEB_BUILD.md §7). Meant for "open the project": starts the last image at
# once and rebuilds only when the code changed since that image (git revision as image label).
#   tools/web_local.sh           start (rebuild if needed)
#   tools/web_local.sh --build   always rebuild, then start
#   tools/web_local.sh --stop    stop the container
# PORT overrides the host port (default 3110, port block 1, D-187).
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."

image="soulwick-game:local"
container="soulwick-game-local"
port="${PORT:-3110}"

if [[ "${1:-}" == "--stop" ]]; then
	docker rm -f "$container" > /dev/null 2>&1 || true
	echo "web_local: stopped"
	exit 0
fi

# Uncommitted changes count as a new revision, so a rebuild picks them up.
rev="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
	rev="$rev-dirty-$(git diff HEAD | sha1sum | cut -c1-8)"
fi
built="$(docker image inspect -f '{{ index .Config.Labels "org.soulwick.rev" }}' "$image" 2> /dev/null || true)"

if [[ "${1:-}" == "--build" || "$built" != "$rev" ]]; then
	echo "web_local: building $image for $rev (was: ${built:-none}), takes a few minutes ..."
	# Rootless Podman runs RUN steps in the host network, where `nginx -t` may not bind port 80; a private netns may.
	extra=()
	if docker --version 2> /dev/null | grep -qi podman; then extra=(--network=private); fi
	docker build "${extra[@]}" --build-arg SOULWICK_ENV=local --label "org.soulwick.rev=$rev" -t "$image" .
fi

docker rm -f "$container" > /dev/null 2>&1 || true
docker run -d --name "$container" -p "$port:80" "$image" > /dev/null
echo "web_local: http://localhost:$port ($rev)"
