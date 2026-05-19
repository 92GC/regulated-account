module regulated_account::compliance;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, HolderAuthority, Time};
use regulated_account::caps::{Self, FeeCap, FreezeCap, PauseCap, PolicyCap, RegistrationCap};
use regulated_account::policy_events;
use regulated_account::fees;
use regulated_account::keys::{Self, HolderKey, IdentityKey};
use regulated_account::validation;

const ENotAuthorized: u64 = 5;
const EPublicCreditDisabled: u64 = 13;

public fun set_kyc<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    asset::assert_valid_kyc_status(status);
    validation::assert_external_ref_hash(&external_ref_hash);
    asset::set_kyc(asset, identity, status, expires_ms, external_ref_hash);
    policy_events::emit_kyc_updated(asset::id(asset), identity, status, expires_ms, external_ref_hash);
}

public fun remove_kyc<T>(asset: &mut Asset<T>, cap: &PolicyCap<T>, identity: IdentityKey) {
    caps::assert_policy(asset::id(asset), cap);
    if (asset::remove_kyc(asset, identity)) {
        policy_events::emit_kyc_updated(asset::id(asset), identity, asset::kyc_unknown(), 0, vector[]);
    };
}

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

public fun authorize_package<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    package_addr: address,
) {
    caps::assert_policy(asset::id(asset), cap);
    asset::authorize_package(asset, package_addr);
    policy_events::emit_package_authorization_updated(asset::id(asset), package_addr, true);
}

public fun deauthorize_package<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    package_addr: address,
) {
    caps::assert_policy(asset::id(asset), cap);
    asset::deauthorize_package(asset, package_addr);
    policy_events::emit_package_authorization_updated(asset::id(asset), package_addr, false);
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

public fun set_fee_config<T>(
    asset: &mut Asset<T>,
    cap: &FeeCap<T>,
    time: Time,
    bps: u64,
    fixed: u64,
    receiver: &Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_fee(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    let now_ms = authority::time_to_option(time);
    set_fee_config_internal(asset, bps, fixed, receiver, &now_ms);
    policy_events::emit_fee_config_updated(
        asset::id(asset),
        bps,
        fixed,
        option::some(account::id(receiver)),
        reason_hash,
    );
}

public fun clear_fee_config<T>(
    asset: &mut Asset<T>,
    cap: &FeeCap<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_fee(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    asset::clear_fee(asset);
    policy_events::emit_fee_config_updated(asset::id(asset), 0, 0, option::none(), reason_hash);
}

public fun freeze_account<T>(
    asset: &Asset<T>,
    cap: &FreezeCap<T>,
    account: &mut Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_freeze(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    account::assert_asset(account, asset::id(asset));
    account::set_frozen(account, true);
    policy_events::emit_freeze(asset::id(asset), account::id(account), true, reason_hash);
}

public fun thaw<T>(
    asset: &Asset<T>,
    cap: &FreezeCap<T>,
    account: &mut Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_freeze(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    account::assert_asset(account, asset::id(asset));
    account::set_frozen(account, false);
    policy_events::emit_freeze(asset::id(asset), account::id(account), false, reason_hash);
}

public fun set_locked_balance<T>(
    asset: &Asset<T>,
    cap: &FreezeCap<T>,
    account: &mut Account<T>,
    locked_balance: u64,
    reason_hash: vector<u8>,
) {
    caps::assert_freeze(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    account::assert_asset(account, asset::id(asset));
    account::set_locked_balance(account, locked_balance);
    policy_events::emit_locked_balance_updated(asset::id(asset), account::id(account), locked_balance, reason_hash);
}

public fun set_account_flags<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    account: &mut Account<T>,
    memo_required: bool,
    allow_public_credits: bool,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    account::assert_asset(account, asset::id(asset));
    account::set_flags(account, memo_required, allow_public_credits);
    policy_events::emit_account_flags_updated(
        asset::id(asset),
        account::id(account),
        memo_required,
        allow_public_credits,
        reason_hash,
    );
}

public fun lock_owner<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_registration(asset::id(asset), cap);
    account::assert_asset(account, asset::id(asset));
    validation::assert_external_ref_hash(&reason_hash);
    account::lock_owner(account);
    policy_events::emit_owner_locked(asset::id(asset), account::id(account), reason_hash);
}

public fun set_holder<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    holder: HolderKey,
    reason_hash: vector<u8>,
) {
    caps::assert_registration(asset::id(asset), cap);
    account::assert_asset(account, asset::id(asset));
    validation::assert_external_ref_hash(&reason_hash);
    account::set_holder(account, holder);
    policy_events::emit_holder_updated(asset::id(asset), account::id(account), holder, reason_hash);
}

public fun set_identity<T>(
    asset: &mut Asset<T>,
    cap: &RegistrationCap<T>,
    time: Time,
    account: &mut Account<T>,
    identity: IdentityKey,
    reason_hash: vector<u8>,
) {
    caps::assert_registration(asset::id(asset), cap);
    account::assert_asset(account, asset::id(asset));
    validation::assert_external_ref_hash(&reason_hash);
    let now_ms = authority::time_to_option(time);
    asset::assert_identity_allowed(asset, identity, &now_ms);
    let previous_identity = account::set_identity(account, identity);
    if (account::balance(account) > 0 && previous_identity != identity) {
        asset::transfer_positive_account_identity(asset, previous_identity, identity);
    };
    policy_events::emit_identity_updated(asset::id(asset), account::id(account), identity, reason_hash);
}

public(package) fun assert_public_credit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    assert!(account::allow_public_credits(account), EPublicCreditDisabled);
    asset::assert_identity_allowed(asset, account::identity(account), now_ms);
}

public(package) fun assert_fee_receiver<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    account::assert_asset(account, asset::id(asset));
    account::assert_not_frozen(account);
    assert_public_credit_allowed(asset, account, now_ms);
}

public(package) fun assert_public_debit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    asset::assert_identity_allowed(asset, account::identity(account), now_ms);
}

public(package) fun assert_authorized<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    holder_authority: HolderAuthority<T>,
) {
    let (kind, addr, witness) = authority::unpack(holder_authority);
    if (authority::is_owner(kind)) {
        assert!(keys::is_holder_address(account::holder(account)), ENotAuthorized);
        assert!(keys::holder_addr(account::holder(account)) == addr, ENotAuthorized);
    } else if (authority::is_package(kind)) {
        assert!(keys::is_holder_package(account::holder(account)), ENotAuthorized);
        assert!(keys::holder_addr(account::holder(account)) == addr, ENotAuthorized);
        assert!(witness.is_some(), ENotAuthorized);
        let witness_name = *witness.borrow();
        assert!(
            asset::package_authorized(asset, addr) ||
                asset::witness_authorized(asset, witness_name),
            ENotAuthorized,
        );
    } else {
        assert!(false, ENotAuthorized);
    };
}

public(package) fun set_fee_config_internal<T>(
    asset: &mut Asset<T>,
    bps: u64,
    fixed: u64,
    receiver: &Account<T>,
    now_ms: &Option<u64>,
) {
    fees::assert_valid(bps, fixed);
    assert_fee_receiver(asset, receiver, now_ms);
    asset::set_fee(asset, fees::new(bps, fixed, account::id(receiver)));
}
