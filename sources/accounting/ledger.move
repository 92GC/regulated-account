module regulated_account::ledger;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, HolderAuthority, Time};
use regulated_account::caps::{Self, BurnCap, ClawbackCap, MintCap};
use regulated_account::authorization;
use regulated_account::events;
use regulated_account::kyc_proof::{Self, KycApproval};
use regulated_account::validation;

public fun mint<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    time: Time,
    approvals: vector<KycApproval<T>>,
    to: &mut Account<T>,
    amount: u64,
) {
    mint_internal(asset, cap, to, amount, authority::time_to_option(time), &approvals);
    kyc_proof::destroy_all(approvals);
}

public fun burn<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    approvals: vector<KycApproval<T>>,
    account: &mut Account<T>,
    amount: u64,
) {
    authorization::assert_authorized(asset, account, holder_authority);
    burn_internal(asset, account, amount, false, authority::time_to_option(time), &approvals, vector[]);
    kyc_proof::destroy_all(approvals);
}

/// Admin burn can debit frozen or locked balance.
public fun admin_burn<T>(
    asset: &mut Asset<T>,
    cap: &BurnCap<T>,
    account: &mut Account<T>,
    amount: u64,
    reason_hash: vector<u8>,
) {
    caps::assert_burn(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    let approvals = vector[];
    burn_internal(
        asset,
        account,
        amount,
        true,
        option::none(),
        &approvals,
        reason_hash,
    );
    approvals.destroy_empty();
}

/// Admin recovery transfer that can debit frozen or locked balance.
public fun clawback<T>(
    asset: &mut Asset<T>,
    cap: &ClawbackCap<T>,
    time: Time,
    approvals: vector<KycApproval<T>>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    reason_hash: vector<u8>,
) {
    caps::assert_clawback(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    validation::assert_positive_amount(amount);
    account::assert_asset(from, asset::id(asset));
    account::assert_asset(to, asset::id(asset));
    // Clawback is a recovery path: source freeze state does not block the debit,
    // but the destination must still be eligible to receive.
    account::assert_not_frozen(to);
    let now_ms = authority::time_to_option(time);
    asset::assert_identity_not_frozen(asset, account::identity(to));
    authorization::assert_public_credit_allowed(asset, to, &now_ms, &approvals);
    force_debit_account(asset, from, amount);
    credit_account(asset, to, amount);
    events::emit_clawback(asset::id(asset), account::id(from), account::id(to), amount, reason_hash);
    kyc_proof::destroy_all(approvals);
}

public(package) fun credit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    credit_internal(asset, account, amount);
}

public(package) fun debit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    let became_zero = account::debit(account, amount);
    if (became_zero) {
        asset::unregister_positive_account(asset, account::identity(account));
    };
}

public(package) fun force_debit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    let became_zero = account::force_debit(account, amount);
    if (became_zero) {
        asset::unregister_positive_account(asset, account::identity(account));
    };
}

public(package) fun prepare_transferable_debit<T>(
    account: &Account<T>,
    amount: u64,
) {
    account::prepare_transferable_debit(account, amount);
}

fun mint_internal<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    now_ms: Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    caps::assert_mint(asset::id(asset), cap);
    validation::assert_positive_amount(amount);
    asset::assert_mint_open(asset);
    asset::assert_not_paused(asset);
    account::assert_asset(to, asset::id(asset));
    account::assert_not_frozen(to);
    asset::assert_identity_not_frozen(asset, account::identity(to));
    // Mint uses the same recipient credit gate as transfers.
    authorization::assert_public_credit_allowed(asset, to, &now_ms, approvals);
    asset::increase_supply(asset, amount);
    credit_internal(asset, to, amount);
    events::emit_mint(asset::id(asset), account::id(to), amount);
}

fun burn_internal<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
    admin_burn: bool,
    now_ms: Option<u64>,
    approvals: &vector<KycApproval<T>>,
    reason_hash: vector<u8>,
) {
    account::assert_asset(account, asset::id(asset));
    validation::assert_positive_amount(amount);
    if (!admin_burn) {
        asset::assert_not_paused(asset);
        account::assert_not_frozen(account);
        asset::assert_identity_not_frozen(asset, account::identity(account));
        authorization::assert_public_debit_allowed(asset, account, &now_ms, approvals);
        account::prepare_transferable_debit(account, amount);
        debit_account(asset, account, amount);
    } else {
        force_debit_account(asset, account, amount);
    };
    asset::decrease_supply(asset, amount);
    events::emit_burn(asset::id(asset), account::id(account), amount, admin_burn, reason_hash);
}

fun credit_internal<T>(asset: &mut Asset<T>, account: &mut Account<T>, amount: u64) {
    let was_zero = account::credit(account, amount);
    if (was_zero) {
        asset::register_positive_account(asset, account::identity(account));
    };
}
