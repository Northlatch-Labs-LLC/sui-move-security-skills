# sui-move-security-skills

Sui-native security skills for Claude Code and any agentskills.io client; no reentrancy
theatre.

Published by **Northlatch Labs LLC**, under
[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).

Move has no dynamic dispatch, so reentrancy does not exist on Sui the way it does on the
EVM; integer overflow already aborts by default. Porting an EVM audit checklist here mostly
ports the wrong list. This pack is nine skills, each one detector for a failure class that
is real on Sui — a shift that is allowed to overflow when arithmetic is not, a shared object
with no capability check, a capability leaked through a return value or a dynamic field, a
one-time witness constructed twice, an ability granted where it should not be, a visibility
that turns an internal helper into public attack surface, an upgrade cap handled without the
digest and version discipline an upgrade needs, a hot-potato struct that never gets consumed
in the same transaction, an oracle or a `Coin<T>` type matched by suffix instead of full type.

## The nine skills

| skill | one line |
|---|---|
| `checked-shlw-overflow` | Every `<<`/`>>` and every hand-rolled "checked" overflow guard on fixed-point or scaled arithmetic — anchored to the Cetus incident of 2025-05-22, where a wrong mask in `checked_shlw` let a left shift overflow silently. **Built. Complete.** |
| `shared-object-access-control` | Every `public fun` taking `&mut` a shared object with no capability parameter and no sender check — callable by anyone, in any order, in any PTB. |
| `capability-leakage` | A capability returned from a public function, stored in a dynamic field anyone can read, or carrying `store` where nothing was meant to move it. |
| `one-time-witness` | An `init(otw: T, ctx)` where the witness is stored instead of consumed, or a second path can construct the same witness type. |
| `ability-misuse` | `key`/`store`/`copy`/`drop` granted beyond what the type's role requires — a `Coin` given `copy`, a capability given `drop`, an object meant to be soulbound given `store`. |
| `visibility-escalation` | A `public` function that should be `public(package)` or private, and a `friend`/package-visibility boundary that does not match the trust boundary the design intends. |
| `upgrade-cap-hygiene` | `UpgradeCap` custody, the `compatible` policy's constraints on signatures and layouts, and the deployed-digest guard that must never let `ci-expected-digest` and `ci-next-digest` hold the same value across a live ceremony. |
| `ptb-hot-potato` | A struct with no abilities that must be consumed in the same transaction — every constructor paired against every consumer, across a programmable transaction block. |
| `oracle-spoof-token` | A price or coin type compared by name suffix instead of full `type_name` (package address included), and an oracle read with no staleness or deviation bound. |

Only `checked-shlw-overflow` is built in this release (`v0.1.0`). The other eight are named,
scoped and load-bearing on the table above; each ships as a full `SKILL.md` in its own
detector's release, never as a stub inside a partial one.

## Trust posture

This pack runs against source code you are already trusted to read. It is built so that
trust does not have to be extended past that:

- **Minimal `allowed-tools`.** Every skill declares only the tools its method needs — `Read`,
  `Grep`, `Bash` scoped to `sui move build` / `sui move test` / `grep` / read-only `git`. No
  skill in this pack asks for network access, write access outside the package under review,
  or credentials of any kind.
- **No shell fetches.** No skill's method step runs `curl`, `wget`, `sh -c` piped from a
  remote source, or any command that reaches the network. Static and property-testing layers
  only; nothing here calls out.
- **Every skill is self-contained.** A `SKILL.md` plus its `references/` is the whole
  detector — no shared runtime, no hidden dependency on another skill in the pack, no import
  of code from outside the file you are reading.
- **How to verify the pack is clean.** Run `scripts/check-pack.sh` from the pack root. It
  confirms every `SKILL.md` carries `name`, `description` and `allowed-tools` in its
  frontmatter, and that no skill file contains `curl`, `wget`, `sh -c`, or any other network
  fetch. The script's own output is the audit trail — read it before you install anything.

## Licence

**CC-BY-SA-4.0** — Attribution-ShareAlike 4.0 International. Full text: [`LICENSE`](LICENSE),
fetched from [creativecommons.org/licenses/by-sa/4.0/legalcode](https://creativecommons.org/licenses/by-sa/4.0/legalcode).
Use, adapt and redistribute any skill in this pack, including commercially, provided you
credit Northlatch Labs LLC and license your derivative under the same terms. This mirrors
the licence Trail of Bits uses for its own published security methodology; a public
detector pack is a deliberate exception to this company's default of proprietary skills
(engineering workstream A1, decided 2026-09-04), attribution kept and forks kept open by
the share-alike term.

## Attribution

Built by Northlatch Labs LLC. The `checked-shlw-overflow` worked example, its test, and its
mutation were written and run on Northlatch Labs LLC's own machine for this pack; the Cetus
root-cause facts in `skills/checked-shlw-overflow/references/cetus-root-cause.md` are drawn
from public post-incident write-ups, each cited by URL, with no more than a short quoted
fragment from any one source.

## The funnel

These skills catch what a human reviewer or these skills' own method would catch by reading
the code. They do not run your test suite through mutation, they do not check a deployed
digest against source, and they do not watch an upgrade for drift. That is
**[ProtocolX Verify](https://github.com/Northlatch-Labs-LLC/protocolx-verify)** — five
gates in your own CI (build, deployed-digest guard, tests, framework pin, mutation smoke),
free for one public repository, $149/repo/month beyond that. Start with these skills; when
you want the same discipline running on every pull request, that is what Verify is for.

---

**Northlatch Labs LLC** — [weir.social](https://weir.social) · [protocolx.io](https://protocolx.io)
