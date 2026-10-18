# syntax=docker/dockerfile:1
# soulwick-game image: the web build of the game (Godot "Web" preset) behind nginx, installable as
# an app (PWA). Build context: repository root. Dokploy app soulwick-game, see docs/WEB_BUILD.md.
#   docker build -t soulwick-game .                                         # development (default)
#   docker build --build-arg SOULWICK_ENV=production -t soulwick-game .
#   docker run --rm -p 18080:80 soulwick-game                               # http://localhost:18080
# Layers: Godot and the web export template are cached (stage godot); a change of the game only
# runs the export again (stage export); nginx (stage runtime) is cached as well.

ARG GODOT_VERSION=4.7.2

# ---------------------------------------------------------------------------------------------
FROM docker.io/library/debian:bookworm-slim AS godot
ARG GODOT_VERSION
# SHA-512 of Godot_v4.7.2-stable_linux.x86_64.zip from SHA512-SUMS.txt of the official release
# (github.com/godotengine/godot-builds/releases/tag/4.7.2-stable).
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65
# The "Web" preset is single-threaded: only web_nothreads_release.zip (plus version.txt) is taken
# out of the 1.3 GB template archive. SHA-512 of the two files inside the official
# Godot_v4.7.2-stable_export_templates.tpz (whose own SHA-512 is ca4d71c4…ccb84079).
ARG WEB_TEMPLATE_SHA512=33a52b6d9b1ce32d3683caaa3ea4b997a3f84c76a92a2e4a98a115b46da55d887854c9ef49bbf3b45b9629938110837978132c3a8cda26d278eb020bd6a9b8ea
ARG VERSION_TXT_SHA512=1a068c1a5338ef144813775d7d1964fb4f03b3aa1142f9a01ce1666c411c4a43eebb0f0b8eb958ec7625d623264e743c6ca92fbf2890d88f9788bff30043e65f
ARG RELEASE_URL=https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable

RUN apt-get update \
	&& apt-get install -y --no-install-recommends ca-certificates curl unzip python3 brotli libfontconfig1 \
	&& rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 3 -o /tmp/godot.zip "${RELEASE_URL}/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" \
	&& echo "${GODOT_SHA512}  /tmp/godot.zip" | sha512sum -c - \
	&& unzip -q /tmp/godot.zip -d /tmp/godot \
	&& mv "/tmp/godot/Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot \
	&& rm -rf /tmp/godot.zip /tmp/godot \
	&& godot --headless --version

COPY deploy/web/fetch_template.py /tmp/fetch_template.py
RUN python3 /tmp/fetch_template.py "${RELEASE_URL}/Godot_v${GODOT_VERSION}-stable_export_templates.tpz" \
		"/root/.local/share/godot/export_templates/${GODOT_VERSION}.stable" \
		"web_nothreads_release.zip=${WEB_TEMPLATE_SHA512}" "version.txt=${VERSION_TXT_SHA512}"

# ---------------------------------------------------------------------------------------------
FROM godot AS export
# development or production: selects API and relay addresses (online/online_config.gd), written
# into online/environment.cfg exactly like tools/export_build.sh does. local = the services of
# `bun dev` in soulwick-platform (http://localhost:8787, ws://localhost:8790), for a container on
# this machine only.
ARG SOULWICK_ENV=development
WORKDIR /project
COPY . .

# Audio lives in Git LFS. A clone without LFS (Dokploy) only has pointer files: then the sounds are
# synthesized with the same generators that made them (AGENTS.md §8). Pointers that remain (own
# .ogg/.mp3 files) are removed, so the game falls back to the generated .wav.
RUN set -eu; \
	pointers() { grep -rlI --include='*.wav' --include='*.ogg' --include='*.mp3' '^version https://git-lfs' audio || true; }; \
	if [ -n "$(pointers)" ]; then \
		echo "Audio files are Git LFS pointers: synthesizing them (tools/generate_audio.py, tools/generate_music.py)."; \
		python3 tools/generate_audio.py; \
		python3 tools/generate_music.py; \
		for file in $(pointers); do echo "  removed remaining LFS pointer: $file"; rm -f "$file"; done; \
	fi

RUN set -eu; \
	case "$SOULWICK_ENV" in development|production|local) ;; \
		*) echo "SOULWICK_ENV must be development, production or local, not '$SOULWICK_ENV'." >&2; exit 1 ;; \
	esac; \
	sed -i "s/^env[[:space:]]*=.*/env=\"${SOULWICK_ENV}\"/" online/environment.cfg; \
	grep -q "^env=\"${SOULWICK_ENV}\"" online/environment.cfg; \
	python3 deploy/web/web_preset.py export_presets.cfg

# The import cache survives between builds (BuildKit cache mount): only changed files are imported.
RUN --mount=type=cache,id=soulwick-godot-import,target=/project/.godot,sharing=locked \
	set -eu; \
	godot --headless --audio-driver Dummy --path . --import; \
	mkdir -p /out; \
	godot --headless --audio-driver Dummy --path . --export-release "Web" /out/index.html; \
	test -s /out/index.html && test -s /out/index.pck && test -s /out/index.wasm

# Font of the start page (SIL OFL, licence next to it); boot splash of the engine is not used.
# 404 page; service worker patched (offline start from "/", font and icons cached:
# deploy/web/patch_service_worker.py). Pre-compressed copies for nginx (brotli_static,
# gzip_static). robots.txt and X-Robots-Tag: only production may appear in search engines.
RUN set -eu; \
	cd /out; \
	rm -f index.png; \
	mkdir -p fonts /nginx; \
	cp /project/art/fonts/PixelifySans-Variable.ttf /project/art/fonts/OFL-PixelifySans.txt fonts/; \
	cp /project/deploy/web/404.html 404.html; \
	python3 /project/deploy/web/patch_service_worker.py /out; \
	if [ "$SOULWICK_ENV" = production ]; then \
		printf 'User-agent: *\nAllow: /\n' > robots.txt; \
		printf '# production: no extra headers\n' > /nginx/soulwick-env.conf; \
	else \
		printf 'User-agent: *\nDisallow: /\n' > robots.txt; \
		printf 'add_header X-Robots-Tag "noindex, nofollow" always;\n' > /nginx/soulwick-env.conf; \
	fi; \
	files="$(find . -type f \( -name '*.wasm' -o -name '*.pck' -o -name '*.js' -o -name '*.html' -o -name '*.json' -o -name '*.ttf' \))"; \
	echo "$files" | xargs -P "$(nproc)" -n 1 gzip -9 -k -n; \
	echo "$files" | xargs -P "$(nproc)" -n 1 brotli -q 9 -k; \
	ls -la /out /out/fonts

# ---------------------------------------------------------------------------------------------
FROM docker.io/library/alpine:3.22 AS runtime
RUN apk add --no-cache nginx nginx-mod-http-brotli
COPY deploy/web/nginx.conf /etc/nginx/nginx.conf
COPY --from=export /nginx/soulwick-env.conf /etc/nginx/soulwick-env.conf
COPY --from=export /out /usr/share/nginx/html
RUN nginx -t
EXPOSE 80
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
	CMD wget -q -O /dev/null http://127.0.0.1/healthz || exit 1
CMD ["nginx", "-g", "daemon off;"]
