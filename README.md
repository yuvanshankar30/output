# JustinProgOutput

JustinProgOutput is the version-controlled archive for manufacturing G-code
emitted by JustinProg (JProg) in Spartans Hub. It provides a shared, auditable
location for CNC programs and keeps output available to the team and the CNC
controller.

## Repository Layout

Programs are organized by UTC production date:

```text
JustinProgOutput/YYYYMMDD/<program>.ngc
JustinProgOutput/YYYYMMDD/<program>.tap
```

The date directory is created automatically when the first program is emitted
on a given day. File extensions identify the controller format:

- `.ngc`: LinuxCNC
- `.tap`: ShopSabre WinCNC

Program names are based on the sheet name and emission group selected in
JustinProg.

## How Output Is Published

JustinProg stores emitted programs in the Manufacturing Files Storage bucket
and publishes the corresponding output here through the authenticated
`jprog-output` Supabase Edge Function.

Files added manually through the Manufacturing Files tab are organized into
the current UTC date directory, or retained in an existing date directory when
added there. Accepted changes are committed so the repository provides an
auditable history of CNC output.

## Full Pipeline (Two Write Paths, One Repo)

There are two independent ways this repository's content changes, and this
machine (`/Users/yuvan/Output`) stays in sync with both automatically:

```text
                 ┌─────────────────────────────────────────┐
                 │   GitHub: yuvanshankar30/output (main)   │
                 └───────────────┬───────────────┬─────────┘
                                  │               │
                     git push    │               │  git fetch/pull
                        ▲        │               │        │
                        │        ▼               ▼        │
   ┌────────────────────┴──┐          ┌──────────────────────────────┐
   │ This machine:          │          │ Spartans Hub web app          │
   │ /Users/yuvan/Output    │          │ (Output Repository editor,    │
   │ + sort_and_push.sh     │          │ Manufacturing > Files tab)     │
   │ + launchd LaunchAgent  │          │ writes via GitHub Contents API │
   └────────────────────────┘          │ (jprog-output-manage Edge Fn)  │
                                        └──────────────────────────────┘
```

- **Web app → GitHub**: every upload/rename/delete/new-folder done through
  the Output Repository editor (the modal opened from `/nesting`, or the
  `JustinProgOutput` folder inside `/manufacture/files`) is its own commit,
  made directly against GitHub via the `jprog-output-manage` Supabase Edge
  Function - there is no local git checkout involved on that side at all.
- **This machine ↔ GitHub**: `sort_and_push.sh` (below) both pushes local
  drops up and pulls remote commits (including ones made through the web
  editor) down, so this checkout never drifts from the real repo in either
  direction.

## Local Sync (`sort_and_push.sh`)

`sort_and_push.sh`, at the root of this checkout, keeps this machine's copy
of the repo in sync with GitHub. It's run automatically by a launchd
LaunchAgent (`~/Library/LaunchAgents/com.spartans.jprog-output-sort.plist`),
triggered two ways:

- **`WatchPaths`** - fires the moment something changes on disk under
  `/Users/yuvan/Output` or `/Users/yuvan/Output/JustinProgOutput` (e.g.
  JustinProg or this script's own previous run dropping a file there).
- **`StartInterval`** - also fires on a 2-minute timer regardless of local
  activity, since a change made *only* on GitHub (via the web editor)
  never touches this machine's disk and so would never trip `WatchPaths`
  on its own.

Each run does, in order:

1. **Pull first.** `git fetch origin main`, then `git pull --rebase
   --autostash` if this checkout is behind - this is what brings down
   renames/uploads/deletes made through the web editor. Best-effort: a
   failed fetch (offline) or a pull conflict is logged and the run
   continues rather than aborting.
2. **Sort.** Any `.ngc`/`.tap` file sitting directly at the repo root or
   directly inside `JustinProgOutput/` (not yet in a dated folder) is
   moved into `JustinProgOutput/<today, Pacific time>/`.
3. **Push.** Stages everything under `JustinProgOutput/`, using git's
   rename detection so a local rename/delete of a `.ngc`/`.tap` file syncs
   to GitHub as a real rename/delete rather than a delete+re-add. Deleting
   anything else there is reverted instead of ever reaching GitHub. Also
   re-pushes any earlier commit that's still queued locally (e.g. a push
   that failed because GitHub had moved on) even if this particular run
   has nothing new of its own to stage.

Logs: `/tmp/jprog-output-sort.log` (what the script itself did),
`/tmp/jprog-output-sort.stdout.log` / `.stderr.log` (raw process output,
launchd-managed).

`README.md` and `sort_and_push.sh` are locked with macOS's immutable flag
(`chflags uchg`) so neither can be edited or deleted by accident (including
by the script's own `git add -A`, which is scoped to `JustinProgOutput/`
only and never touches the repo root). To change either file: `chflags
nouchg README.md sort_and_push.sh`, make the edit, then `chflags uchg
README.md sort_and_push.sh` again.

## CNC Controller Setup

On the CNC controller, run the following from the local repository checkout
before using newly published output:

```bash
cd /path/to/output
git fetch && git pull
```

Run the update only when the machine is in a safe state and no program is
actively running.

## Before Machining

Select the required program from the appropriate date directory and verify the
following before running it:

- Machine and controller format
- Stock and workholding
- Tooling and setup
- Work origin and units
- Program contents and intended operation

This repository is an output archive and does not replace the operator's
normal CNC verification process.
