#!/usr/bin/env bash
# Mirror Confluence Cloud spaces to local Markdown files.
#
# Driven entirely by environment variables, set by `caco sync-confluence'
# from the declarative data in confluence.scm:
#   CONFLUENCE_BASE_URL   e.g. https://acme.atlassian.net
#   CONFLUENCE_EMAIL      Atlassian account email
#   CONFLUENCE_TOKEN      API token (https://id.atlassian.com/manage-profile/security/api-tokens)
#   CONFLUENCE_SPACES     space keys, whitespace separated; empty = all spaces
#   CONFLUENCE_DEST       target directory
#
# The mirror is exact: pages deleted in Confluence disappear locally.
set -euo pipefail

: "${CONFLUENCE_BASE_URL:?}" "${CONFLUENCE_EMAIL:?}" "${CONFLUENCE_TOKEN:?}" "${CONFLUENCE_DEST:?}"
for tool in curl jq pandoc rsync; do
  command -v "$tool" >/dev/null || { echo "missing tool: $tool" >&2; exit 1; }
done

base="${CONFLUENCE_BASE_URL%/}"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

api() { curl -fsS -u "$CONFLUENCE_EMAIL:$CONFLUENCE_TOKEN" -H 'Accept: application/json' "$1"; }

slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g' | cut -c1-80; }

# Print "id<TAB>key" lines for the spaces to mirror.
list_spaces() {
  local url="$base/wiki/api/v2/spaces?limit=250" page
  while [ -n "$url" ]; do
    page="$(api "$url")"
    jq -r --arg keys "${CONFLUENCE_SPACES:-}" '
      ($keys | split(" ") | map(select(. != ""))) as $want
      | .results[] | select(($want | length) == 0 or (.key | IN($want[])))
      | "\(.id)\t\(.key)"' <<<"$page"
    url="$(jq -r '._links.next // empty' <<<"$page")"
    [ -n "$url" ] && url="$base$url"
  done
}

sync_space() {
  local id="$1" key="$2" out="$stage/$key" url page n=0
  mkdir -p "$out"
  url="$base/wiki/api/v2/spaces/$id/pages?body-format=storage&limit=100"
  while [ -n "$url" ]; do
    page="$(api "$url")"
    while IFS= read -r row; do
      local pid title version html file
      pid="$(jq -r .id <<<"$row")"
      title="$(jq -r .title <<<"$row")"
      version="$(jq -r '.version.createdAt // ""' <<<"$row")"
      html="$(jq -r '.body.storage.value // ""' <<<"$row")"
      file="$out/$(slug "$title")-$pid.md"
      {
        printf -- '---\ntitle: "%s"\nconfluence_id: %s\nspace: %s\nupdated: %s\nurl: %s\n---\n\n' \
          "${title//\"/\\\"}" "$pid" "$key" "$version" "$base/wiki/spaces/$key/pages/$pid"
        printf '%s' "$html" | pandoc -f html -t gfm --wrap=none
      } >"$file"
      n=$((n + 1))
    done < <(jq -c '.results[]' <<<"$page")
    url="$(jq -r '._links.next // empty' <<<"$page")"
    [ -n "$url" ] && url="$base$url"
  done
  echo "space $key: $n pages"
}

while IFS=$'\t' read -r id key; do
  sync_space "$id" "$key"
done < <(list_spaces)

if [ -z "$(ls -A "$stage")" ]; then
  echo "nothing fetched; refusing to wipe $CONFLUENCE_DEST" >&2
  exit 1
fi

mkdir -p "$CONFLUENCE_DEST"
rsync -a --delete --exclude '.git' "$stage/" "$CONFLUENCE_DEST/"
echo "synced to $CONFLUENCE_DEST"
