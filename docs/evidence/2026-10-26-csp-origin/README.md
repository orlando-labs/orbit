# CSP and origin working-tree verification

The application passes `assets.csp` to `SecurityPolicy(origin:)`; no CSP string or application origin middleware remains. The core default header is unchanged.

[Summary](summary.json) records source hashes, strict full-native coverage and verification limits. The focused policy fixture is also part of the stage-3 suite. Browser tests cover login, session lifecycle, errors, production permissions and the development HMR connection. OAuth uses the local Sputnik provider fixture.
