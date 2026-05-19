module regulated_account::ledger;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, HolderAuthority, Time};
use regulated_account::caps::{Self, BurnCap, ClawbackCap, MintCap};
use regulated_account::compliance;
use regulated_account::events;
use regulated_account::validation;

const EPublicCreditDisabled: u64 = 13;
const EInvalidRestrictedLot: u64 = 32;

public fun mint<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    time: Time,
    to: &mut Account<T>,
    amount: u64,
) {
    mint_internal(asset, cap, to, amount, authority::time_to_option(time), true);
}

public fun mint_restricted<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    time: Time,
    to: &mut Account<T>,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
) {
    let now_ms = authority::time_to_option(time);
    validation::assert_external_ref_hash(&external_ref_hash);
    assert!(now_ms.is_some(), EInvalidRestrictedLot);
    assert!(unlock_ms > *now_ms.borrow(), EInvalidRestrictedLot);
    // The credit and restricted lot are recorded in one transaction, so callers never observe
    // credited-but-unlocked restricted mint state.
    mint_internal(asset, cap, to, amount, now_ms, false);
    account::prune_unlocked_restricted_lots(to, &now_ms);
    account::add_restricted_lot(to, amount, unlock_ms, external_ref_hash);
    events::emit_restricted_mint(asset::id(asset), account::id(to), amount, unlock_ms, external_ref_hash);
}

public fun burn<T>(
    asset: &mut Asset<T>,
    holder_authority: HolderAuthority<T>,
    time: Time,
    account: &mut Account<T>,
    amount: u64,
) {
    compliance::assert_authorized(asset, account, holder_authority);
    burn_internal(asset, account, amount, false, authority::time_to_option(time), vector[]);
}

public fun admin_burn<T>(
    asset: &mut Asset<T>,
    cap: &BurnCap<T>,
    account: &mut Account<T>,
    amount: u64,
    reason_hash: vector<u8>,
) {
    caps::assert_burn(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    burn_internal(asset, account, amount, true, option::none(), reason_hash);
}

public fun clawback<T>(
    asset: &mut Asset<T>,
    cap: &ClawbackCap<T>,
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
    account::assert_not_frozen(to);
    assert!(account::allow_public_credits(to), EPublicCreditDisabled);
    force_debit_account(asset, from, amount);
    credit_recovery_account(asset, to, amount);
    events::emit_clawback(asset::id(asset), account::id(from), account::id(to), amount, reason_hash);
}

public(package) fun credit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    credit_internal(asset, account, amount, true);
}

public(package) fun credit_fee_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    credit_internal(asset, account, amount, false);
}

public(package) fun credit_recovery_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    credit_internal(asset, account, amount, false);
}

public(package) fun debit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    let became_zero = account::debit(account, amount);
    if (became_zero) {
        asset::unregister_positive_account(asset, account::identity(account));
    } else {
        asset::assert_min_positive_balance(asset, account::balance(account));
    };
}

public(package) fun debit_account_without_min_check<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    let became_zero = account::debit(account, amount);
    if (became_zero) {
        asset::unregister_positive_account(asset, account::identity(account));
    };
}

public(package) fun assert_account_min_positive_balance<T>(
    asset: &Asset<T>,
    account: &Account<T>,
) {
    asset::assert_min_positive_balance(asset, account::balance(account));
}

public(package) fun force_debit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    let became_zero = account::force_debit(account, amount);
    if (became_zero) {
        asset::unregister_positive_account(asset, account::identity(account));
    } else {
        asset::assert_min_positive_balance(asset, account::balance(account));
    };
}

public(package) fun prepare_transferable_debit<T>(
    account: &mut Account<T>,
    amount: u64,
    now_ms: &Option<u64>,
) {
    account::prepare_transferable_debit(account, amount, now_ms);
}

fun mint_internal<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    now_ms: Option<u64>,
    emit_event: bool,
) {
    caps::assert_mint(asset::id(asset), cap);
    validation::assert_positive_amount(amount);
    asset::assert_mint_open(asset);
    asset::assert_not_paused(asset);
    account::assert_asset(to, asset::id(asset));
    account::assert_not_frozen(to);
    compliance::assert_public_credit_allowed(asset, to, &now_ms);
    let new_supply = asset::increase_supply(asset, amount);
    asset::assert_display_supply(asset, new_supply);
    credit_account(asset, to, amount);
    if (emit_event) {
        events::emit_mint(asset::id(asset), account::id(to), amount);
    };
}

fun burn_internal<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
    admin_burn: bool,
    now_ms: Option<u64>,
    reason_hash: vector<u8>,
) {
    account::assert_asset(account, asset::id(asset));
    validation::assert_positive_amount(amount);
    if (!admin_burn) {
        asset::assert_not_paused(asset);
        account::assert_not_frozen(account);
        compliance::assert_public_debit_allowed(asset, account, &now_ms);
        account::prepare_transferable_debit(account, amount, &now_ms);
        debit_account(asset, account, amount);
    } else {
        force_debit_account(asset, account, amount);
    };
    asset::decrease_supply(asset, amount);
    events::emit_burn(asset::id(asset), account::id(account), amount, admin_burn, reason_hash);
}

fun credit_internal<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
    enforce_min_positive_balance: bool,
) {
    let was_zero = account::credit(account, amount);
    if (was_zero) {
        asset::register_positive_account(asset, account::identity(account));
    };
    if (enforce_min_positive_balance) {
        asset::assert_min_positive_balance(asset, account::balance(account));
    };
}
