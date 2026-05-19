module regulated_account::transfer;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, HolderAuthority, Time};
use regulated_account::compliance;
use regulated_account::events;
use regulated_account::fees;
use regulated_account::ledger;
use regulated_account::validation;

const EFeeReceiverRequired: u64 = 15;
const EUseTransferWithFee: u64 = 16;

public fun transfer<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    compliance::assert_authorized(asset, from, holder_authority);
    transfer_internal(asset, from, to, amount, memo, authority::time_to_option(time));
}

public fun transfer_with_fee_account<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    compliance::assert_authorized(asset, from, holder_authority);
    transfer_with_fee_internal(asset, from, to, fee_account, amount, memo, authority::time_to_option(time));
}

public fun transfer_with_sender_fee_account<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    compliance::assert_authorized(asset, from, holder_authority);
    transfer_with_sender_fee_internal(asset, from, to, amount, memo, authority::time_to_option(time));
}

public fun transfer_with_recipient_fee_account<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    compliance::assert_authorized(asset, from, holder_authority);
    transfer_with_recipient_fee_internal(asset, from, to, amount, memo, authority::time_to_option(time));
}

fun transfer_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    validation::assert_positive_amount(amount);
    assert_common_transfer(asset, from, to, &memo, &now_ms);
    let fee_amount = fees::compute(asset::fee(asset), amount);
    assert!(fee_amount == 0, EUseTransferWithFee);
    ledger::prepare_transferable_debit(from, amount, &now_ms);
    ledger::debit_account(asset, from, amount);
    ledger::credit_account(asset, to, amount);
    events::emit_transfer(
        asset::id(asset),
        account::id(from),
        account::id(to),
        option::none(),
        amount,
        fee_amount,
        amount,
        memo,
    );
}

fun transfer_with_fee_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    validation::assert_positive_amount(amount);
    assert_common_transfer(asset, from, to, &memo, &now_ms);
    account::assert_asset(fee_account, asset::id(asset));
    account::assert_not_frozen(fee_account);
    compliance::assert_public_credit_allowed(asset, fee_account, &now_ms);
    ledger::prepare_transferable_debit(from, amount, &now_ms);
    let (fee_amount, net_amount, receiver_id) = fees::configured(asset::fee(asset), amount);
    assert!(account::id(fee_account) == receiver_id, EFeeReceiverRequired);
    ledger::debit_account(asset, from, amount);
    ledger::credit_account(asset, to, net_amount);
    ledger::credit_fee_account(asset, fee_account, fee_amount);
    events::emit_transfer(
        asset::id(asset),
        account::id(from),
        account::id(to),
        option::some(receiver_id),
        amount,
        fee_amount,
        net_amount,
        memo,
    );
}

fun transfer_with_sender_fee_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    validation::assert_positive_amount(amount);
    assert_common_transfer(asset, from, to, &memo, &now_ms);
    let (fee_amount, net_amount, receiver_id) = fees::configured(asset::fee(asset), amount);
    assert!(account::id(from) == receiver_id, EFeeReceiverRequired);
    ledger::prepare_transferable_debit(from, amount, &now_ms);
    ledger::debit_account_without_min_check(asset, from, amount);
    if (net_amount > 0) {
        ledger::credit_account(asset, to, net_amount);
    };
    ledger::credit_fee_account(asset, from, fee_amount);
    ledger::assert_account_min_positive_balance(asset, from);
    events::emit_transfer(
        asset::id(asset),
        account::id(from),
        account::id(to),
        option::some(receiver_id),
        amount,
        fee_amount,
        net_amount,
        memo,
    );
}

fun transfer_with_recipient_fee_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    validation::assert_positive_amount(amount);
    assert_common_transfer(asset, from, to, &memo, &now_ms);
    ledger::prepare_transferable_debit(from, amount, &now_ms);
    let (fee_amount, net_amount, receiver_id) = fees::configured(asset::fee(asset), amount);
    assert!(account::id(to) == receiver_id, EFeeReceiverRequired);
    ledger::debit_account(asset, from, amount);
    ledger::credit_account(asset, to, amount);
    events::emit_transfer(
        asset::id(asset),
        account::id(from),
        account::id(to),
        option::some(receiver_id),
        amount,
        fee_amount,
        net_amount,
        memo,
    );
}

fun assert_common_transfer<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    memo: &vector<u8>,
    now_ms: &Option<u64>,
) {
    asset::assert_not_paused(asset);
    account::assert_asset(from, asset::id(asset));
    account::assert_asset(to, asset::id(asset));
    account::assert_not_frozen(from);
    account::assert_not_frozen(to);
    compliance::assert_public_debit_allowed(asset, from, now_ms);
    compliance::assert_public_credit_allowed(asset, to, now_ms);
    account::assert_memo(to, memo);
}
