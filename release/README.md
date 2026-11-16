The registry reference is `slowpilot/orbit`.

Build the current SDK first, then run:

```sh
./release/prepare
./release/prepare --config orm.json
./release/prepare --config notebook.json
```

Set `SPUTNIK_ROOT` when the SDK checkout is not the sibling `sputnik-lang`.
The Sputnik recipe creates publisher-scoped imports, exact package dependencies
and relocatable archives under `release/out`. Use `--out` to choose another
directory. `--modules bytecode` supports modules without exported macros.
Mixed variants retain macro provider sources. The tool inspects the archive
before returning its path. Publication is a separate step.

Build and publish `slowpilot/orbit` before its `slowpilot/orbit-notebook`
companion. The companion selects the exact Orbit release in `notebook.json`.
