# Cetus Protocol incident, 2025-05-22 — root cause, from public sources

This page summarizes, in Northlatch Labs LLC's own words, what public post-incident write-ups
report about the Cetus Protocol exploit. Every factual claim below is attributed to the
source that carries it; quoted fragments are short and marked with quotation marks. Nothing
here is copied from Cetus's own source code — none of these sources publish it in full, and
this page does not attempt to reconstruct it beyond the closed-form expressions already
derivable from the public description of the bug.

## What happened

Cetus Protocol, a decentralized exchange on Sui, was exploited on 2025-05-22 for
approximately $223 million. The loss traces to a single arithmetic defect in a shared
fixed-point math library used by the protocol's liquidity calculations.

## The defect, as reported

- The vulnerable function is `checked_shlw`, a helper meant to guard a left-shift-by-64 used
  while computing token deltas in Cetus's fixed-point math.
- BlockSec's incident writeup states the flawed implementation used
  `"0xffffffffffffffff << 192"` as its threshold where `"1 << 192"` was the correct one, and
  describes the consequence as letting values "greater than 2^192 but smaller than this
  erroneous mask" pass the check despite causing silent truncation on the shift.
  Source: [blocksec.com — "Cetus Incident: One Unchecked Shift Drains $223M"](https://blocksec.com/blog/cetus-incident-one-unchecked-shift-drains-223m-largest)
- Dedaub's analysis names the same function and the same flawed mask line,
  `"let mask = 0xffffffffffffffff << 192;"`, states the intended check was
  "`n >= (1 << 192)`", and describes the exploit input as roughly `2^113` for the liquidity
  parameter and roughly `2^79` for a price delta, whose product crosses the 192-bit boundary
  the guard was supposed to enforce; it reports the resulting truncated numerator produced a
  required deposit of "1 unit of token A" against a liquidity position "worth billions of
  tokens."
  Source: [dedaub.com — "The Cetus AMM $200M Hack: How a Flawed 'Overflow' Check Led to Catastrophic Loss"](https://dedaub.com/blog/the-cetus-amm-200m-hack-how-a-flawed-overflow-check-led-to-catastrophic-loss/)
- Additional independent write-ups covering the same root cause and timeline, listed here for
  cross-reference and not individually quoted:
  - [Halborn — "Explained: The Cetus Hack (May 2025)"](https://www.halborn.com/blog/post/explained-the-cetus-hack-may-2025)
  - [Cyfrin — "Inside The $223M Cetus Exploit: Root Cause And Impact Analysis"](https://www.cyfrin.io/blog/inside-the-223m-cetus-exploit-root-cause-and-impact-analysis)
  - [QuillAudits — "Cetus Protocol Hack: Overflow Bug Leads to $223M Loss"](https://quillaudits.medium.com/cetus-protocol-hack-overflow-bug-leads-to-223m-loss-0bafd07d83e9)
  - [Verichains — "Cetus Protocol Hacked Analysis"](https://blog.verichains.io/p/cetus-protocol-hacked-analysis)
  - [OWASP Smart Contract Top 10 — SC09:2026 Integer Overflow and Underflow](https://scs.owasp.org/sctop10/SC09-IntegerOverflowUnderflow/)

## Why this is a Sui-specific class, not a ported EVM one

Move aborts by default on overflow for `+`, `-`, `*`. It does not abort on shift overflow —
`<<`/`>>` wrap silently, the same as raw EVM arithmetic before Solidity 0.8's checked math.
A team that reasonably trusts "Move checks my arithmetic for me" can still ship exactly this
defect, because the one operator class Move does not check by default is the one the guard
existed to cover. This is why `checked-shlw-overflow` treats every custom shift guard as
higher suspicion than an unguarded shift: an absent guard is at least visibly absent, while
a present-but-wrong guard reads as safety and was, in this incident, the entire vulnerability.

## What this page does not claim

- This page does not reproduce Cetus's actual source. The worked example in
  `skills/checked-shlw-overflow/SKILL.md` is a standalone, minimal reproduction of the
  arithmetic pattern described above, written independently for this pack, compiled and
  tested on this machine — not a copy of the exploited code.
- The exact exploit transaction, attacker addresses, and fund-recovery timeline are covered
  in the sources above and are out of scope for this detector, which addresses the guard
  defect itself.
