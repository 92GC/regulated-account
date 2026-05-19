module regulated_account::amount_math;

const EAmountOverflow: u64 = 25;
const EInvalidDisplayScale: u64 = 28;

public(package) fun checked_add(left: u64, right: u64): u64 {
    assert!(left <= std::u64::max_value!() - right, EAmountOverflow);
    left + right
}

public(package) fun scaled_u64(value: u64, numerator: u64, denominator: u64): u64 {
    assert!(numerator > 0 && denominator > 0, EInvalidDisplayScale);
    let scaled = (value as u128) * (numerator as u128) / (denominator as u128);
    assert!(scaled <= (std::u64::max_value!() as u128), EAmountOverflow);
    (scaled as u64)
}

public(package) fun assert_scalable_u64(value: u64, numerator: u64, denominator: u64) {
    let _scaled = scaled_u64(value, numerator, denominator);
}

public(package) fun checked_scaled_u64(
    value: u64,
    numerator: u64,
    denominator: u64,
): Option<u64> {
    if (numerator == 0 || denominator == 0) {
        return option::none()
    };

    let scaled = (value as u128) * (numerator as u128) / (denominator as u128);
    if (scaled <= (std::u64::max_value!() as u128)) {
        option::some(scaled as u64)
    } else {
        option::none()
    }
}
