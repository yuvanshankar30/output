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
