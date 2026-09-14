# JustinProgOutput

This repository is the public, version-controlled mirror of manufacturing
G-code emitted by JustinProg (JProg) in Spartans Hub.

## Layout

Programs are organized by UTC production date:

```text
JustinProgOutput/YYYYMMDD/<program>.ngc
JustinProgOutput/YYYYMMDD/<program>.tap
```

The date folder is created automatically when the first program is emitted on
that day. `.ngc` files are LinuxCNC programs. `.tap` files are ShopSabre
WinCNC programs. Program names use the sheet name and emission group selected
in JustinProg.

## How Files Arrive

JustinProg uploads emitted programs to the Manufacturing Files Storage bucket
and publishes the same content here through the authenticated Supabase
`jprog-output` Edge Function. Operators can also add `.ngc` or `.tap` files
manually in the Manufacturing Files tab. Files added at the
`JustinProgOutput` root are placed in the current UTC date folder; files added
inside an existing date folder stay with that date. Each accepted change is
committed so the repository remains an auditable output history.

## CNC Use

Download or inspect the required program from the appropriate date folder
before running it on the CNC controller. Confirm the machine, stock, tooling,
workholding, origin, units, and program type before machining. This repository
is an output archive, not a substitute for the operator's normal verification
process.

## CNC Controller Setup

Clone this repository once on the computer that controls the CNC machine:

```bash
git clone https://github.com/yuvanshankar30/output.git
cd output
```

Before using new output, update the local checkout:

```bash
cd /path/to/output
git fetch origin
git pull --ff-only origin main
```

Run the update only when the machine is in a safe state and no program is actively running. If the pull cannot be fast-forwarded, stop and resolve the checkout manually rather than overwriting local files.
