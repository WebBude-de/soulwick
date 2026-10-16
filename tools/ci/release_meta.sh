#!/usr/bin/env bash
# Decides version, server environment, tag and pre-release flag of a release run (release.yml,
# docs/RELEASE.md). Writes key=value lines to $GITHUB_OUTPUT (or stdout when it is not set).
#
# Input (environment):
#   EVENT            push | workflow_dispatch
#   REF_TYPE         tag | branch (github.ref_type); a branch push is a dev build (D-157)
#   TAG              pushed tag (github.ref_name), e.g. v0.9.1 or v0.9.1-beta.1
#   INPUT_ENV        workflow_dispatch: development | production
#   INPUT_PRERELEASE workflow_dispatch: true | false
#   RELEASE_ENV      repository variable: environment of a tag without suffix (default development)
#   RUN_NUMBER       github.run_number (unique tag of manual pre-releases)
#
# Rules:
#   - The version is application/config/version in project.godot. A pushed tag without "v" and
#     without suffix must equal it (same check as tools/export_build.*), otherwise the run stops.
#   - Tag without suffix (v0.9.1): environment = RELEASE_ENV, default development. Development stays
#     the default until the production servers run and the project member switches (D-148).
#   - Tag with suffix (v0.9.1-beta.1): always development.
#   - Manual run: environment and pre-release from the form; the tag is v<version> for a full
#     release and v<version>-<dev|rc>.<run> for a pre-release (created by the release job).
#   - Push to the dev branch: environment development, pre-release, tag v<version>-dev.<run>
#     (created by the release job), like a manual development run (D-157).
#   - Every development build is a pre-release: it talks to the test servers.
#   - store_code: Android versionCode of the Google Play bundle and iOS build number. Every upload
#     to a store needs a new, bigger number, also for test builds of one version:
#     (major*10000 + minor*100 + patch) * 100 + slot, slot = 99 for a full release (v0.9.1),
#     the trailing number of a pre-release tag (v0.9.1-beta.3 -> 3, v0.9.1-dev.17 -> 17, at most 98),
#     otherwise 1. 0.9.1 -> 90199, 0.9.1-beta.3 -> 90103. The APK keeps the short code (0.9.1 -> 901),
#     so APKs built on the PC still install as updates.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EVENT="${EVENT:-workflow_dispatch}"

fail() {
	echo "::error::$1" >&2
	exit 1
}

version="$(sed -n 's/^config\/version="\([^"]*\)".*/\1/p' "$ROOT/project.godot" | head -n 1)"
[ -n "$version" ] || fail "project.godot has no application/config/version."
echo "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || fail "application/config/version '$version' is not of the form X.Y.Z."

prerelease=false
if [ "$EVENT" = "push" ] && [ "${REF_TYPE:-tag}" = "branch" ]; then
	environment=development
	prerelease=true
	tag="v$version-dev.${RUN_NUMBER:-0}"
	create_tag=true
elif [ "$EVENT" = "push" ]; then
	tag="${TAG:-}"
	case "$tag" in v*) ;; *) fail "Release tags start with v (got '$tag')." ;; esac
	tag_version="${tag#v}"
	base="${tag_version%%-*}"
	[ "$base" = "$version" ] || fail "Tag $tag does not match application/config/version $version in project.godot. Set the version first or fix the tag."
	if [ "$tag_version" != "$base" ]; then
		prerelease=true
		environment=development
	else
		environment="${RELEASE_ENV:-development}"
	fi
	create_tag=false
else
	environment="${INPUT_ENV:-development}"
	case "${INPUT_PRERELEASE:-true}" in true|false) prerelease="${INPUT_PRERELEASE:-true}" ;; *) fail "prerelease must be true or false." ;; esac
	[ "$environment" = "development" ] && prerelease=true
	if [ "$prerelease" = "true" ]; then
		suffix=rc
		[ "$environment" = "development" ] && suffix=dev
		tag="v$version-$suffix.${RUN_NUMBER:-0}"
	else
		tag="v$version"
	fi
	create_tag=true
fi

case "$environment" in
	development|production) ;;
	*) fail "Unknown environment '$environment' (RELEASE_ENV or form: development | production)." ;;
esac
[ "$environment" = "development" ] && prerelease=true

base_code="$(echo "$version" | awk -F. '{ print $1 * 10000 + $2 * 100 + $3 }')"
suffix="${tag#v"$version"}"
if [ -z "$suffix" ]; then
	slot=99
else
	slot="$(echo "$suffix" | sed -n 's/.*[^0-9]\([0-9][0-9]*\)$/\1/p')"
	slot="${slot:-1}"
	slot="$((10#$slot))"
	[ "$slot" -ge 1 ] || slot=1
	[ "$slot" -le 98 ] || slot=98
fi
store_code="$((base_code * 100 + slot))"

echo "Soulwick $version: tag $tag, environment $environment, pre-release $prerelease, store code $store_code" >&2
out="${GITHUB_OUTPUT:-/dev/stdout}"
{
	echo "version=$version"
	echo "environment=$environment"
	echo "prerelease=$prerelease"
	echo "tag=$tag"
	echo "create_tag=$create_tag"
	echo "store_code=$store_code"
} >> "$out"
