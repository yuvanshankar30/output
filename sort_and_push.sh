#!/bin/bash
# Watches JustinProgOutput/ for files dropped directly at its top level
# (not yet inside a dated YYYYMMDD folder), moves each into
# JustinProgOutput/<today's date>/ to match the existing convention, then
# commits and pushes. Triggered by a launchd LaunchAgent (WatchPaths) -
# see com.spartans.jprog-output-sort.plist.
set -euo pipefail

REPO_DIR="/Users/yuvan/output"
DROP_DIR="$REPO_DIR/JustinProgOutput"
LOG_FILE="/tmp/jprog-output-sort.log"
LOCK_DIR="/tmp/jprog-output-sort.lock"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"; }

# Portable atomic lock (flock isn't available on macOS) - launchd can fire
# this script again while a previous run (or the git writes it makes) is
# still in flight; skip rather than run two pushes concurrently.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$LOCK_DIR"' EXIT

cd "$REPO_DIR"

TODAY=$(date +%Y%m%d)
moved=()

while IFS= read -r -d '' file; do
  mkdir -p "$DROP_DIR/$TODAY"
  base="$(basename "$file")"
  # Don't clobber a same-named file already sorted today.
  dest="$DROP_DIR/$TODAY/$base"
  if [ -e "$dest" ]; then
    dest="$DROP_DIR/$TODAY/$(date +%H%M%S)-$base"
  fi
  mv "$file" "$dest"
  moved+=("$base")
  log "Moved $base -> ${dest#$REPO_DIR/}"
done < <(find "$DROP_DIR" -maxdepth 1 -type f -print0)

if [ ${#moved[@]} -eq 0 ]; then
  exit 0
fi

git add -A
if git diff --cached --quiet; then
  log "Nothing staged after move, skipping commit"
  exit 0
fi

message="Add $(IFS=', '; echo "${moved[*]}")"
git commit -m "$message" >> "$LOG_FILE" 2>&1
if git push origin main >> "$LOG_FILE" 2>&1; then
  log "Pushed: $message"
else
  log "PUSH FAILED for: $message (commit is still local - will retry pushing next time this runs)"
fi
