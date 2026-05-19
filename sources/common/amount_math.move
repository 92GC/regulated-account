module regulated_account::amount_math;

const EAmountOverflow: u64 = 25;

public(package) fun checked_add(left: u64, right: u64): u64 {
    assert!(left <= std::u64::max_value!() - right, EAmountOverflow);
    left + right
}

public(package) fun checked_sub(left: u64, right: u64): u64 {
    assert!(left >= right, EAmountOverflow);
    left - right
}
