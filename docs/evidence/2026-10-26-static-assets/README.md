# Streaming public assets

`assets/favicon.svg` is served by Sputnik through `orbit.assets.StaticFiles()`, before sessions and CSRF. The favicon action and inline SVG source are removed. The application does not import telemetry.

[Summary](summary.json) records working-tree source hashes, native coverage, verification and limits. Both the assets fixture and the application have zero native fallback and no telemetry module. Nine browser tests passed across production VM, development VM and production native. SDK fixtures also pass in VM and strict full-native.
