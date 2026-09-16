#!/bin/bash
# Watches the repo root and JustinProgOutput/ for .ngc/.tap files dropped
# directly at either top level (not yet inside a dated YYYYMMDD folder),
# moves each into JustinProgOutput/<today's date>/ to match the existing
# convention, then commits and pushes.
#
# Also mirrors LOCAL RENAMES under JustinProgOutput/ to GitHub, but never
# mirrors a plain local DELETE - deleting a file here only removes the
# local copy; git's own content-similarity detection (git diff -M) is what
# tells a genuine rename (paired delete+add of the same content) apart from
# a standalone delete, which gets restored instead of ever reaching GitHub.
#
# Triggered by a launchd LaunchAgent (WatchPaths) - see
# com.spartans.jprog-output-sort.plist.
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

# Finder scatters .DS_Store into every folder it browses - delete stray
# ones outright rather than ever treating them as a real drop. .gitignore
# keeps them from being tracked at all; this just cleans up any that
# landed before that took effect.
find "$REPO_DIR" -name ".DS_Store" -not -path "*/.git/*" -delete

TODAY=$(date +%Y%m%d)
moved=()

# Real gcode output can land at the repo root or directly in
# JustinProgOutput/ - either way it belongs in today's dated folder.
# Restricted to .ngc/.tap specifically (same convention $lib/jprog_output.js
# already enforces app-side) - NEVER sweep up arbitrary repo-root files
# like README.md or this script itself, which live at the repo root
# permanently and are not "dropped output."
for scan_dir in "$REPO_DIR" "$DROP_DIR"; do
  [ -d "$scan_dir" ] || continue
  while IFS= read -r -d '' file; do
    mkdir -p "$DROP_DIR/$TODAY"
    base="$(basename "$file")"
    dest="$DROP_DIR/$TODAY/$base"
    if [ -e "$dest" ]; then
      dest="$DROP_DIR/$TODAY/$(date +%H%M%S)-$base"
    fi
    mv "$file" "$dest"
    moved+=("$base")
    log "Moved $base -> ${dest#$REPO_DIR/}"
  done < <(find "$scan_dir" -maxdepth 1 -type f \( -iname "*.ngc" -o -iname "*.tap" \) -print0)
done

# Stage every change under JustinProgOutput/ (new drops, renames, deletes)
# so git's own -M similarity detection below can tell a rename (a deletion
# paired with a same-content addition) apart from a standalone delete.
git add -A -- "$DROP_DIR"

if git diff --cached --quiet -- "$DROP_DIR"; then
  exit 0
fi

# A standalone delete (not part of a detected rename) must never reach
# GitHub - restore it so the local copy comes back too, keeping this
# machine's folder and the repo in sync rather than silently diverging.
restored=()
while IFS=$'\t' read -r status path; do
  [ "$status" = "D" ] || continue
  git restore --staged --worktree -- "$path"
  restored+=("$path")
  log "Restored $path (local deletes never delete from GitHub)"
done < <(git diff --cached --name-status -M -- "$DROP_DIR")

if git diff --cached --quiet -- "$DROP_DIR"; then
  log "Nothing left staged after restoring deletes"
  exit 0
fi

# Build the commit message from what's actually staged (adds/renames),
# not just what this run happened to move - a manual git mv done outside
# this script gets swept in here too.
summary=$(git diff --cached --name-status -M -- "$DROP_DIR" | awk -F'\t' '
  $1=="A"{printf "Add %s; ", $2}
  $1 ~ /^R/{printf "Rename %s -> %s; ", $2, $3}
' | sed 's/; $//')
message="${summary:-Update JustinProgOutput}"

git commit -q -m "$message" >> "$LOG_FILE" 2>&1
if git push origin main >> "$LOG_FILE" 2>&1; then
  log "Pushed: $message"
else
  log "PUSH FAILED for: $message (commit is still local - will retry pushing next time this runs)"
fi
