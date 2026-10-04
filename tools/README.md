# tools/

Pinned so that every verdict in this repository is reproducible byte for byte.
Both are MIT-licensed and redistributed unmodified.

| File | Version | SHA-256 |
| --- | --- | --- |
| `tla2tools.jar` | TLA+ tools nightly, built 2026-10-02 (git `1813307`) | `b490f45c1de08e4ff9753259a00338981b9cf464f01ca9e9cd5f19f33cf0bb92` |
| `CommunityModules-deps.jar` | tlaplus/CommunityModules release `202609120237` | `3d9a282c360e90d55e9bbe99caa2987d508fef1556d652760b4af4455e283733` |

The nightly is required: the trace module uses `Json` and `IOUtils` from
CommunityModules, which the 2.19 release of the tools cannot load.

Sources:
- https://nightly.tlapl.us/dist/tla2tools.jar
- https://github.com/tlaplus/CommunityModules/releases/tag/202609120237
