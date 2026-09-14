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
