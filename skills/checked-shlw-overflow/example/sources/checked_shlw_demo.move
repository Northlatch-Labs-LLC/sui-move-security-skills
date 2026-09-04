/// Minimal, compiling reproduction of the Cetus-class `checked_shlw` defect
/// (Cetus Protocol, Sui mainnet, 2025-05-22 — see references/cetus-root-cause.md
/// in the sui-move-security-skills pack for sources).
///
/// The real bug lived in a shared fixed-point math library's overflow guard
/// for a left-shift-by-64 helper used while computing a token amount from a
/// liquidity value. This module isolates that one guard, buggy and fixed,
/// with nothing else attached, so it compiles and tests standalone.
module checked_shlw_demo::fixed_point {

    /// THE DEFECT. `checked_shlw` is meant to guard `n << 64` against
    /// overflowing u256: the only `n` for which the shift does not lose
    /// bits is `n < 2^192`. The guard here compares `n` against
    /// `0xffffffffffffffff << 192` instead of `1 << 192`. Those are not
    /// the same value: `0xffffffffffffffff << 192` is
    /// `(2^64 - 1) * 2^192`, i.e. within `2^192` of the u256 maximum — so
    /// almost every unsafe `n` in `[2^192, 2^256)` is still `<= mask` and
    /// passes the check, then silently truncates on the shift because Move
    /// does not abort on shift overflow (only on `+`, `-`, `*`).
    public fun checked_shlw_buggy(n: u256): u256 {
        let mask: u256 = 0xffffffffffffffffu256 << 192; // WRONG bound
        assert!(n <= mask, 0);
        n << 64
    }

    /// THE FIX. The only values that survive the shift intact are those
    /// with no bit set at or above position 192.
    public fun checked_shlw_fixed(n: u256): u256 {
        let bound: u256 = 1u256 << 192; // correct bound
        assert!(n < bound, 0);
        n << 64
    }
}
