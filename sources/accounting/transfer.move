module regulated_account::transfer;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, HolderAuthority, Time};
use regulated_account::authorization;
use regulated_account::events;
use regulated_account::kyc_proof::{Self, KycApproval};
use regulated_account::ledger;
use regulated_account::validation;

public fun transfer<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    approvals: vector<KycApproval<T>>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    authorization::assert_authorized(asset, from, holder_authority);
    transfer_internal(asset, from, to, amount, memo, authority::time_to_option(time), &approvals);
    kyc_proof::destroy_all(approvals);
}

fun transfer_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    validation::assert_positive_amount(amount);
    assert_common_transfer(asset, from, to, &memo, &now_ms, approvals);
    ledger::prepare_transferable_debit(from, amount, &now_ms);
    ledger::debit_account(asset, from, amount);
    ledger::credit_account(asset, to, amount);
    events::emit_transfer(
        asset::id(asset),
        account::id(from),
        account::id(to),
        amount,
        memo,
    );
}

fun assert_common_transfer<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    memo: &vector<u8>,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    asset::assert_not_paused(asset);
    account::assert_asset(from, asset::id(asset));
    account::assert_asset(to, asset::id(asset));
    account::assert_not_frozen(from);
    account::assert_not_frozen(to);
    asset::assert_identity_not_frozen(asset, account::identity(from));
    asset::assert_identity_not_frozen(asset, account::identity(to));
    authorization::assert_public_debit_allowed(asset, from, now_ms, approvals);
    authorization::assert_public_credit_allowed(asset, to, now_ms, approvals);
    account::assert_memo(to, memo);
}
