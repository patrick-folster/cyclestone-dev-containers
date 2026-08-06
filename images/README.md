# Images

Owns base and child image definitions. The image maintainer owns implementation;
changes to a documented public image contract require `@patrick-folster` approval.
Do not place provider-specific behavior here unless it is part of an image line.

`base/Containerfile` is the sole OCI definition for the `1.x` non-provider base.
Its adjacent package manifest, immutable version data, acquisition script, and
entrypoint are explicit build inputs. See [the base-image guide](../docs/base-image.md).
