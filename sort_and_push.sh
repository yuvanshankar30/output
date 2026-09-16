#!/bin/bash
# Watches the repo root and JustinProgOutput/ for .ngc/.tap files dropped
# directly at either top level (not yet inside a dated YYYYMMDD folder),
# moves each into JustinProgOutput/<today's date>/ to match the existing
# convention, then commits and pushes. Also mirrors a LOCAL DELETE of a
# tracked .ngc/.tap file under JustinProgOutput/ to the GitHub repo -
# deleting any other file type is never synced, so accidentally trashing
# something like README.md locally can't delete it from GitHub.
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

# Mirror a local delete of a tracked .ngc/.tap file under JustinProgOutput/
# to GitHub - restrict to gcode files specifically so accidentally
# trashing something else locally (README.md, this script) can never
# delete it from the real repo; restore anything else that went missing.
deleted=()
while IFS= read -r missing; do
  case "$missing" in
    "$DROP_DIR"/*.ngc|"$DROP_DIR"/*.tap|"$DROP_DIR"/*.NGC|"$DROP_DIR"/*.TAP)
      git rm -q --ignore-unmatch -- "$missing"
      deleted+=("$(basename "$missing")")
      log "Deleted $missing (gcode file removed locally)"
      ;;
    *)
      git checkout -q -- "$missing" 2>/dev/null || true
      log "Restored $missing (only .ngc/.tap deletions sync to GitHub)"
      ;;
  esac
done < <(git ls-files --deleted -- "$DROP_DIR")

if [ ${#moved[@]} -eq 0 ] && [ ${#deleted[@]} -eq 0 ]; then
  exit 0
fi

git add -- "$DROP_DIR"
if git diff --cached --quiet; then
  log "Nothing staged after move/delete, skipping commit"
  exit 0
fi

parts=()
[ ${#moved[@]} -gt 0 ] && parts+=("Add $(IFS=', '; echo "${moved[*]}")")
[ ${#deleted[@]} -gt 0 ] && parts+=("Delete $(IFS=', '; echo "${deleted[*]}")")
message=$(IFS='; '; echo "${parts[*]}")

git commit -q -m "$message" >> "$LOG_FILE" 2>&1
if git push origin main >> "$LOG_FILE" 2>&1; then
  log "Pushed: $message"
else
  log "PUSH FAILED for: $message (commit is still local - will retry pushing next time this runs)"
fi
