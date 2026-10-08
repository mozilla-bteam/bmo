# bPopup (vendored)

`bPopup-min.js` is **not** managed via npm/Dependabot like the other third-party
front-end libraries (see `package.json` and `scripts/build-frontend.mjs`).

- Version: **0.11.0**
- Upstream: https://github.com/dinbror/bpopup
- Reason it is vendored: bPopup is not published to the npm registry, so it
  cannot be pinned in `package.json`. The upstream project is effectively
  unmaintained.

If this file needs updating, download the release from the upstream repository
and replace `bPopup-min.js` by hand. Longer term, prefer replacing bPopup with a
maintained modal/dialog dependency that can be npm-managed.
