module regulated_account::fees;

const MAX_BPS: u64 = 10_000;

const EInvalidFee: u64 = 9;
const EFeeReceiverRequired: u64 = 15;
const EFeeTooSmall: u64 = 28;

public struct FeeConfig has copy, drop, store {
    bps: u64,
    fixed: u64,
    receiver: Option<ID>,
}

public(package) fun zero(): FeeConfig {
    FeeConfig { bps: 0, fixed: 0, receiver: option::none() }
}

public(package) fun new(bps: u64, fixed: u64, receiver: ID): FeeConfig {
    assert_valid(bps, fixed);
    FeeConfig { bps, fixed, receiver: option::some(receiver) }
}

public(package) fun assert_valid(bps: u64, fixed: u64) {
    assert!(bps <= MAX_BPS, EInvalidFee);
    assert!(bps > 0 || fixed > 0, EInvalidFee);
    assert!(bps < MAX_BPS || fixed == 0, EInvalidFee);
}

public(package) fun configured(fee: &FeeConfig, amount: u64): (u64, u64, ID) {
    let fee_amount = compute(fee, amount);
    assert!(fee_amount > 0, EFeeTooSmall);
    assert!(fee.receiver.is_some(), EFeeReceiverRequired);
    assert!(amount >= fee_amount, EInvalidFee);
    (fee_amount, amount - fee_amount, *fee.receiver.borrow())
}

public(package) fun compute(fee: &FeeConfig, amount: u64): u64 {
    let value = ((amount as u128) * (fee.bps as u128) / (MAX_BPS as u128)) +
        (fee.fixed as u128);
    assert!(value <= (std::u64::max_value!() as u128), EInvalidFee);
    value as u64
}

public(package) fun receiver(fee: &FeeConfig): Option<ID> {
    fee.receiver
}

public(package) fun bps(fee: &FeeConfig): u64 {
    fee.bps
}

public(package) fun fixed(fee: &FeeConfig): u64 {
    fee.fixed
}
