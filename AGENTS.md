# Borrowed Fire Agent Notes

Read `README.md` first. This repo is the public Borrowed Fire system: skills, doctrine, installer,
tests, and the Prometheus template.

Useful commands:

```sh
./tools/skill-lint.sh
./tests/test-install.sh
./tests/test-brain.sh
```

Keep public repo content free of private Prometheus memory, credentials, local endpoint details,
and machine-specific notes.

`tools/skill-lint.sh` also rejects owner-specific product, machine, and account names when a
private list is present. Keep that list in the brain at `config/public-denylist.txt`, one term per
line, or name another file with `BORROWEDFIRE_PRIVATE_TERMS`. Never commit the list here.
