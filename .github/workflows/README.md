# Workflows

Owns CI, release, and security automation. Workflow maintainers own implementation;
`@patrick-folster` approves changes to required checks, publication, permissions,
or secret access.

`base-image-validation.yml` is a manually dispatched, non-publishing qualification
workflow. It runs the native C1-C3 matrix plus a controlled non-1000 C4/C5
workspace-identity job and retains attributable evidence. Its optional Docker
Build Cloud job produces and audits the combined OCI archive but does not push an
image to a registry.
