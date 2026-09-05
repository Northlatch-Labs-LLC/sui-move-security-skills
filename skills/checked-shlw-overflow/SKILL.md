---
name: checked-shlw-overflow
description: Detects Cetus-class overflow-guard defects in Sui Move fixed-point and scaled-arithmetic code — a hand-rolled "checked" shift guard that compares against the wrong bound, letting a left shift on u64/u128/u256 silently truncate instead of aborting. Use this on any package doing fixed-point math, AMM/curve pricing, liquidity delta calculations, or any custom overflow check around `<<`/`>>`. Move aborts by default on `+`, `-`, `*` overflow; it does NOT abort on shift overflow, so a wrong or missing shift guard is the one arithmetic class Move does not protect for you.
license: CC-BY-SA-4.0
allowed-tools: Read, Grep, Bash(sui move build:*), Bash(sui move test:*), Bash(grep:*), Bash(sui --version)
---

# checked-shlw-overflow

## Anchor: the Cetus incident, 2025-05-22

On 2025-05-22, Cetus Protocol — a DEX on Sui mainnet — lost approximately $223M to a defect
in a shared fixed-point math library's `checked_shlw` function. `checked_shlw` was meant to
guard a left-shift-by-64 used while computing token deltas for liquidity: it should reject
any input `n` that does not fit in the low 192 bits, because only those values survive
`n << 64` inside a u256 without losing bits above bit 255. The guard instead compared `n`
against `0xffffffffffffffff << 192` — which is `(2^64 - 1) * 2^192`, sitting just below the
u256 maximum — instead of the correct bound, `1 << 192`. Almost every unsafe value in
`[2^192, 2^256)` passed the check and then silently truncated on the shift, because **Move
checks arithmetic overflow by default on `+`, `-`, `*`, but shifts are allowed to overflow**.
The attacker supplied a liquidity parameter around `2^113` combined with a price delta
around `2^79`; their product crossed the 192-bit boundary, the wrong-mask guard let it
through, and the truncated result made the required deposit for a massive liquidity
position round down to a handful of token units. Full source citations, with short quoted
fragments only, are in `references/cetus-root-cause.md`.

## When to use

- Any package with fixed-point (Q64.64-style) arithmetic, AMM/curve pricing, or a liquidity
  or swap delta calculation.
- Any function whose name or comment contains "checked", "safe", "overflow" and that touches
  `<<` or `>>`.
- Any scaling step that multiplies then shifts, or shifts then divides, to move between two
  fixed-point precisions.
- Before any publish or upgrade ceremony that touches math on `u64`/`u128`/`u256` — this
  detector is one manual-checklist item inside `engineering:sui-move-audit-method`'s
  layer (a) static pass, and can run standalone before that method is invoked.

## What to look for

1. **Every `<<` and `>>`** on `u64`, `u128` or `u256` in `sources/`, in library code the
   package depends on, and in any vendored copy of a math module.
2. **Every custom "checked" guard** — a function or inline `assert!` whose name or comment
   claims to prevent overflow before a shift, a multiply-then-shift, or a scale conversion.
   The guard itself is the thing under suspicion, not the shift alone: a present guard that
   checks the wrong thing is worse than an absent one, because it reads as safe.
3. **Mask and bound constants** compared against the shift amount or the input. Any literal
   built from `0xfff...f` (a chain of `f`s) shifted left is a signal to hand-recompute what
   value it actually represents and compare that, not the literal's appearance, against the
   type width and the shift amount.
4. **Fixed-point scaling steps** — anywhere a value moves between two different implicit
   decimal precisions (e.g. Q64.64 to a raw integer, or a 1e9-scaled price to 1e18) via a
   shift or a multiply-divide pair. These are exactly where a "checked" helper like
   `checked_shlw` gets written once and reused everywhere, so one wrong bound compromises
   every call site.

## Commands

```bash
sui --version                                          # pin the toolchain in the report

# every shift, every candidate guard, every module that might carry one
grep -rnE '<<|>>' sources/
grep -rniE 'checked_shl|checked_shr|checked_shlw|overflow' sources/
grep -rnE '0x[fF]+' sources/                            # mask-shaped literals worth hand-checking
grep -rnE '\b(shl|shr)\b' sources/

# build and test are the floor; a guard that has no test exercising its
# reject path is unverified regardless of what layer (a)-(f) says about it
sui move build --lint --warnings-are-errors
sui move test
```

For each hit from the `grep -rniE 'checked_shl|checked_shr|checked_shlw|overflow'` line,
open the function, write down its guard's bound as a closed-form expression (not the
literal), and hand-derive the actual safe range for the shift amount and type width before
trusting either.

## Worked analysis

The example below is a minimal, standalone reproduction — not Cetus's own source, which is
not reproduced here — built to isolate the one guard. It lives in full at
`example/` beside this file (`example/sources/checked_shlw_demo.move`,
`example/tests/checked_shlw_demo_tests.move`), compiles under `sui move build` and its
tests run under `sui move test` (verified on `sui 1.78.1-homebrew`, package
`checked_shlw_demo`, both commands exit 0, 3/3 tests pass — `cd` into `example/` and run
both to reproduce).

**The defect** — compare `n` against the wrong mask:

```move
module checked_shlw_demo::fixed_point {

    /// THE DEFECT. Guards `n << 64` against overflowing u256: the only `n`
    /// for which the shift does not lose bits is `n < 2^192`. This guard
    /// compares `n` against `0xffffffffffffffff << 192` instead of
    /// `1 << 192`. Those are not the same value: `0xffffffffffffffff << 192`
    /// is `(2^64 - 1) * 2^192`, within `2^192` of the u256 maximum — so
    /// almost every unsafe `n` in `[2^192, 2^256)` is still `<= mask` and
    /// passes, then silently truncates on the shift, because Move does not
    /// abort on shift overflow (only on `+`, `-`, `*`).
    public fun checked_shlw_buggy(n: u256): u256 {
        let mask: u256 = 0xffffffffffffffffu256 << 192; // WRONG bound
        assert!(n <= mask, 0);
        n << 64
    }
}
```

**The fix** — the only values that survive the shift intact have no bit set at or above
position 192:

```move
    /// THE FIX.
    public fun checked_shlw_fixed(n: u256): u256 {
        let bound: u256 = 1u256 << 192; // correct bound
        assert!(n < bound, 0);
        n << 64
    }
```

**The test that trips it.** `n = 2^195` is far outside the safe range but still `<= mask`
under the buggy guard, so it passes. The shift then wraps modulo `2^256`:
`2^195 << 64 = 2^259 = 8 * 2^256`, so the low 256 bits are exactly `0`. The guard passed and
the answer silently became zero — the same shape as the Cetus loss, where a huge liquidity
value produced a near-zero required deposit:

```move
#[test]
fun buggy_guard_admits_unsafe_value_and_truncates_to_zero() {
    let n: u256 = 1u256 << 195;
    let result = checked_shlw_demo::fixed_point::checked_shlw_buggy(n);
    assert!(result == 0, 0);
}

#[test]
#[expected_failure(abort_code = 0)]
fun fixed_guard_rejects_unsafe_value() {
    let n: u256 = 1u256 << 195;
    checked_shlw_demo::fixed_point::checked_shlw_fixed(n);
}
```

**The two tests that trip the boundary.** The pair above is not enough, and the reason is
worth more than the pair itself. `2^195` is rejected by `n < 2^192` and by `n <= 2^192`
alike, so neither test can tell a correct bound from an off-by-one — the exact mistake
class this skill is about. The safe range is closed on one side and open on the other, so
the boundary needs a test on each side of it:

```move
#[test]
#[expected_failure(abort_code = 0)]
fun fixed_guard_rejects_the_first_unsafe_value() {
    let n: u256 = 1u256 << 192;                     // 2^192 << 64 = 2^256 -> low bits 0
    checked_shlw_demo::fixed_point::checked_shlw_fixed(n);
}

#[test]
fun fixed_guard_accepts_the_largest_safe_value() {
    let n: u256 = (1u256 << 192) - 1;               // -> 2^256 - 2^64, still fits
    let result = checked_shlw_demo::fixed_point::checked_shlw_fixed(n);
    assert!(result == (n << 64), 0);
}
```

All four ran and passed (`sui move test`: 5 passed, 0 failed, counting the buggy-guard
test).

**The mutation that proves the test notices.** Per the estate's move-mutate discipline
(`engineering:move-mutate`): derive one mutation per `assert!` and confirm the suite kills
it. Reintroducing the Cetus-class wrong bound into the *fixed* function —

```diff
- let bound: u256 = 1u256 << 192; // correct bound
+ let bound: u256 = 0xffffffffffffffffu256 << 192; // MUTATION
```

— and re-running `sui move test` turns two tests red (`Test did not error as expected`),
because the guard no longer aborts on the unsafe input.

Do not stop at that one. A whole-bound replacement is a large mutation and almost any
reject-path test kills it; the mutation that actually measures a bound is the one-character
one, and it is the one people ship past:

```diff
- assert!(n < bound, 0);
+ assert!(n <= bound, 0);   // MUTATION: the off-by-one
```

That turns `fixed_guard_rejects_the_first_unsafe_value` red and nothing else. Run the
tightening direction too — `1u256 << 192` to `1u256 << 191` — which turns
`fixed_guard_accepts_the_largest_safe_value` red and nothing else. A bound that only has
tests far outside it is measured in neither direction.

Recorded plainly because this pack got it wrong first: the example shipped with the
whole-bound mutation demonstrated and killed, and the off-by-one survived it silently. A
mutation set that only contains mutations the suite already kills is a decoration, and the
survivor is the entire product of the exercise. A guard with no test that goes red under
the one-character mutation is a coverage gap on a money path, full stop — classify it, do
not wave it through.

## Report shape

For each candidate site found by the commands above:

1. File and line of the shift, and file and line of its guard (if any).
2. The guard's bound, as a closed-form expression, next to the actual safe bound derived by
   hand for that type width and shift amount.
3. Whether a test exists that supplies an input on the wrong side of the *true* boundary
   (not just the guard's own boundary) and whether that test currently passes or fails.
4. If no such test exists: write one (per "the test that trips it" above), run it against
   the guard as found, and record whether it caught anything.
5. The mutation applied to the guard's own `assert!`, and whether the suite killed it.
6. Verdict per site: `clean` (correct bound, proven by a passing reject-path test and a
   killed mutation), `defect` (wrong bound, cite the exact expressions), or `unverified`
   (guard present, no reject-path test exists to trust it either way — this is not a pass).

## Never

- Never "fix" a shift-overflow finding by removing the guard. The correct fix narrows the
  guard to the true safe bound and adds the reject-path test; deleting the guard converts a
  detectable defect into an undetectable one.
- Never trust a library because it was audited. Cetus's `checked_shlw` shipped in a shared
  library that had prior review; the defect survived it. Re-derive the bound yourself for
  every call site that reaches this pack's grep commands, in this package and in every
  dependency it vendors or pins.
- Never accept a guard's own passing test suite as proof if no test in that suite supplies
  an input beyond the guard's claimed boundary. A suite with zero tests on the reject path
  is a suite that cannot tell a correct guard from an absent one.
- Never treat "shift overflow" as covered by Move's default overflow checking. It is not;
  that is the entire reason this failure class exists on Sui.
