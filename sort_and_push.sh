#!/bin/bash
# Watches the repo root and JustinProgOutput/ for .ngc/.tap files dropped
# directly at either top level (not yet inside a dated YYYYMMDD folder),
# moves each into JustinProgOutput/<today's date>/ to match the existing
# convention, then commits and pushes.
#
# Also mirrors LOCAL RENAMES and LOCAL DELETES of .ngc/.tap files under
# JustinProgOutput/ to GitHub - git's own content-similarity detection
# (git diff -M) is what tells a genuine rename (paired delete+add of the
# same content) apart from a standalone delete. Deleting anything else
# (a non-gcode file that isn't already OS-protected, see below) is
# restored instead of ever reaching GitHub - protects against removing
# something unexpected from the real repo.
#
# README.md and this script are additionally locked with macOS's own
# immutable flag (chflags uchg) so they can't be deleted - or edited -
# locally at all, a stronger guarantee than anything this script itself
# can provide. Run `chflags nouchg README.md sort_and_push.sh` first if
# either ever needs to change, then `chflags uchg` them again after.
#
# Triggered by a launchd LaunchAgent (WatchPaths) - see
# com.spartans.jprog-output-sort.plist.
set -euo pipefail

REPO_DIR="/Users/yuvan/Output"
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

# A standalone delete (not part of a detected rename) of a .ngc/.tap file
# is a real, intentional delete - sync it to GitHub. Anything else that
# went missing (a non-gcode file not already OS-locked, see above) is
# restored instead, so an unexpected file type can never quietly
# disappear from the real repo.
deleted=()
restored=()
while IFS=$'\t' read -r status path; do
  [ "$status" = "D" ] || continue
  ext_lower=$(printf '%s' "${path##*.}" | tr '[:upper:]' '[:lower:]')
  if [ "$ext_lower" = "ngc" ] || [ "$ext_lower" = "tap" ]; then
    deleted+=("$path")
    log "Deleting $path (gcode file removed locally)"
  else
    git restore --staged --worktree -- "$path"
    restored+=("$path")
    log "Restored $path (only .ngc/.tap deletions sync to GitHub)"
  fi
done < <(git diff --cached --name-status -M -- "$DROP_DIR")

if git diff --cached --quiet -- "$DROP_DIR"; then
  log "Nothing left staged after restoring deletes"
  exit 0
fi

# Build the commit message from what's actually staged (adds/renames/
# deletes), not just what this run happened to move - a manual git mv or
# rm done outside this script gets swept in here too.
summary=$(git diff --cached --name-status -M -- "$DROP_DIR" | awk -F'\t' '
  $1=="A"{printf "Add %s; ", $2}
  $1=="D"{printf "Delete %s; ", $2}
  $1 ~ /^R/{printf "Rename %s -> %s; ", $2, $3}
' | sed 's/; $//')
message="${summary:-Update JustinProgOutput}"

git commit -q -m "$message" >> "$LOG_FILE" 2>&1
if git push origin main >> "$LOG_FILE" 2>&1; then
  log "Pushed: $message"
else
  log "PUSH FAILED for: $message (commit is still local - will retry pushing next time this runs)"
fi
