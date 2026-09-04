#[test_only]
module checked_shlw_demo::fixed_point_tests {
    use checked_shlw_demo::fixed_point;

    /// n = 2^195 is far outside the safe range (must be < 2^192) but the
    /// buggy mask (0xffffffffffffffff << 192 ~= 2^256 - 2^192) still
    /// admits it: 2^195 <= mask is true. The shift then wraps modulo
    /// 2^256: 2^195 << 64 = 2^259 = 8 * 2^256, so the low 256 bits are
    /// exactly 0. The guard passed and the answer silently became zero —
    /// this is the shape of the Cetus loss (a huge liquidity value producing
    /// a near-zero required deposit).
    #[test]
    fun buggy_guard_admits_unsafe_value_and_truncates_to_zero() {
        let n: u256 = 1u256 << 195;
        let result = fixed_point::checked_shlw_buggy(n);
        assert!(result == 0, 0);
    }

    /// The fixed guard rejects the same value outright.
    #[test]
    #[expected_failure(abort_code = 0)]
    fun fixed_guard_rejects_unsafe_value() {
        let n: u256 = 1u256 << 195;
        fixed_point::checked_shlw_fixed(n);
    }

    /// The fixed guard still accepts and correctly shifts a safe value.
    #[test]
    fun fixed_guard_accepts_safe_value() {
        let n: u256 = 1u256 << 100;
        let result = fixed_point::checked_shlw_fixed(n);
        assert!(result == (n << 64), 0);
    }
}
