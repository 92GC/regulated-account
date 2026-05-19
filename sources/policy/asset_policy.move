module regulated_account::asset_policy;

use regulated_account::asset::{Self, Asset};
use regulated_account::caps::{Self, CloseMintCap, MintCap, PauseCap, PolicyCap};
use regulated_account::policy_events;
use regulated_account::validation;

public fun set_compliance_mode<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    mode: u8,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_mode(asset, mode);
    policy_events::emit_compliance_mode_updated(asset::id(asset), mode, reason_hash);
}

public fun lock_compliance_mode<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::lock_mode(asset);
    policy_events::emit_compliance_mode_locked(asset::id(asset), reason_hash);
}

public fun set_max_supply<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    max_supply: Option<u64>,
    reason_hash: vector<u8>,
) {
    caps::assert_mint(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_max_supply_internal(asset, max_supply);
    policy_events::emit_max_supply_updated(asset::id(asset), max_supply, reason_hash);
}

public fun close_mint<T>(asset: &mut Asset<T>, cap: &CloseMintCap<T>, reason_hash: vector<u8>) {
    caps::assert_close_mint(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::close_mint_internal(asset);
    policy_events::emit_mint_closed(asset::id(asset), reason_hash);
}

public fun set_shareholder_caps<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    max_shareholders: Option<u64>,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_shareholder_cap(asset, max_shareholders);
    policy_events::emit_shareholder_caps_updated(asset::id(asset), max_shareholders, reason_hash);
}

public fun set_min_positive_balance<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    min_positive_balance: u64,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_min_positive_balance(asset, min_positive_balance);
    policy_events::emit_min_positive_balance_updated(asset::id(asset), min_positive_balance, reason_hash);
}

public fun authorize_witness<T, W: drop>(asset: &mut Asset<T>, cap: &PolicyCap<T>) {
    caps::assert_policy(asset::id(asset), cap);
    let witness = asset::authorize_witness<T, W>(asset);
    policy_events::emit_witness_authorization_updated(asset::id(asset), witness, true);
}

public fun deauthorize_witness<T, W: drop>(asset: &mut Asset<T>, cap: &PolicyCap<T>) {
    caps::assert_policy(asset::id(asset), cap);
    let witness = asset::deauthorize_witness<T, W>(asset);
    policy_events::emit_witness_authorization_updated(asset::id(asset), witness, false);
}

public fun pause<T>(asset: &mut Asset<T>, cap: &PauseCap<T>, reason_hash: vector<u8>) {
    caps::assert_pause(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_paused(asset, true);
    policy_events::emit_pause(asset::id(asset), true, reason_hash);
}

public fun unpause<T>(asset: &mut Asset<T>, cap: &PauseCap<T>, reason_hash: vector<u8>) {
    caps::assert_pause(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_paused(asset, false);
    policy_events::emit_pause(asset::id(asset), false, reason_hash);
}

public fun set_default_account_frozen<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    frozen: bool,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::set_default_account_frozen(asset, frozen);
    policy_events::emit_default_account_state_updated(asset::id(asset), frozen, reason_hash);
}
