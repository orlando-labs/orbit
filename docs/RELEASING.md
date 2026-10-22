# Release process

Only a maintainer acting as release manager may publish Orbit. Releases are
built from an annotated SemVer tag and never from an uncommitted worktree.

## Candidate checklist

- [ ] `VERSION`, both `sputnik.toml` files, lock files, public API manifest,
      changelog, migration notes, compatibility matrix, and evidence version
      agree.
- [ ] Dependency revisions and trees are immutable and available to the clean
      resolver; compiler, runtime, and stdlib come from one Sputnik revision.
- [ ] Formatting/static, core, HTTP conformance, fuzz smoke, native,
      integration, representative CRUD/4xx soak smoke, examples,
      documentation, clean-room, and every platform matrix job are green at
      the tagged commit.
- [ ] Package build is byte-identical across two clean builds. Package/source
      checksums and build provenance are attached to the release.
- [ ] No unresolved critical/high security finding, conformance failure, or
      unexplained performance regression exists.
- [ ] Release notes state the trusted-edge profile, known limitations,
      migrations, supported matrix, and whether RC validation is still open.

## Build and tag

```sh
./script/clean-room-build
./script/ci full
git tag -s v1.0.0-rc.1 -m "Orbit 1.0.0-rc.1"
git push origin v1.0.0-rc.1
```

The tag workflow independently verifies `v$VERSION`, repeats the clean build,
builds the package twice, checks byte equality, emits SHA-256 checksums and
machine-readable evidence, and uploads the package/source artifacts. The
release environment supplies `ORBIT_PACKAGE_SIGNING_KEY` and
`ORBIT_PACKAGE_KEY_ID`; these secrets never appear in logs or arguments shown
to users. An unsigned artifact is not published as an official release.

## Post-release

Verify the release checksum/provenance, install from the published registry in
an empty environment, compile the API example, and open the next `Unreleased`
section. For an RC, start the canary/load/soak/fuzz/rollback campaign; do not
change the production-ready claim until every RC gate has immutable evidence.
Use `./script/soak run --duration 72h --artifacts <durable-path>` for the
representative application run and attach its `run.json`, `samples.jsonl`,
`report.json`, and logs to the RC evidence index.

A failed or partially uploaded release is withdrawn, not overwritten. Package
versions and tags are immutable; fixes use a new SemVer version.
