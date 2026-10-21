# Packager Doctor

ComputerCraft program for Create 6: finds out why a packager refuses to unpack packages into an item vault.

It checks:
- vault free slots (every package stack needs room; the whole package must fit or it's rejected)
- whether the packager is actually attached to that vault (it must touch the packager's back)
- whether the packager is still holding a package (it accepts nothing until that leaves)
- every package sitting in other inventories on the modem network, simulating if it would fit

Install:

    wget https://raw.githubusercontent.com/levisnakes/cc-packager-doctor/main/packager_doctor.lua doctor.lua

Put wired modems on the packager and the vault, run `doctor`, press R to re-check.
