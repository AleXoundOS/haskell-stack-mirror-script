setup-info: $MIRROR_URL/stack-setup-mirror.yaml

urls:
  latest-snapshot: $MIRROR_URL/snapshots.json
  lts-build-plans: $MIRROR_URL/build-plans/lts-haskell/
  nightly-build-plans: $MIRROR_URL/build-plans/stackage-nightly/

package-indices:
- name: Hackage
  download-prefix: $MIRROR_URL/packages/
  http: $MIRROR_URL/01-index.tar.gz
