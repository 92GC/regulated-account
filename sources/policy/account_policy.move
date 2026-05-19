module regulated_account::account_policy;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, Time};
use regulated_account::caps::{Self, FreezeCap, PolicyCap, RegistrationCap};
use regulated_account::keys::{HolderKey, IdentityKey};
use regulated_account::kyc_proof::{Self, KycApproval};
use regulated_account::policy_events;
use regulated_account::validation;

public fun freeze_account<T>(
    asset: &mut Asset<T>,
    cap: &FreezeCap<T>,
    account: &mut Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_freeze(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    account::assert_asset(account, asset::id(asset));
    asset::set_identity_frozen(asset, account::identity(account), true);
    account::set_frozen(account, true);
    policy_events::emit_freeze(asset::id(asset), account::id(account), true, reason_hash);
}

public fun thaw<T>(
    asset: &mut Asset<T>,
    cap: &FreezeCap<T>,
    account: &mut Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_freeze(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    account::assert_asset(account, asset::id(asset));
    asset::set_identity_frozen(asset, account::identity(account), false);
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

public fun lock_holder<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    reason_hash: vector<u8>,
) {
    caps::assert_registration(asset::id(asset), cap);
    account::assert_asset(account, asset::id(asset));
    validation::assert_external_ref_hash(&reason_hash);
    account::lock_holder(account);
    policy_events::emit_holder_locked(asset::id(asset), account::id(account), reason_hash);
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
    approvals: vector<KycApproval<T>>,
    account: &mut Account<T>,
    identity: IdentityKey,
    reason_hash: vector<u8>,
) {
    caps::assert_registration(asset::id(asset), cap);
    account::assert_asset(account, asset::id(asset));
    validation::assert_external_ref_hash(&reason_hash);
    let now_ms = authority::time_to_option(time);
    asset::assert_identity_not_frozen(asset, account::identity(account));
    asset::assert_identity_not_frozen(asset, identity);
    asset::assert_identity_credit_allowed_with_approvals(asset, identity, &now_ms, &approvals);
    let previous_identity = account::set_identity(account, identity);
    if (account::balance(account) > 0 && previous_identity != identity) {
        asset::transfer_positive_account_identity(asset, previous_identity, identity);
    };
    policy_events::emit_identity_updated(asset::id(asset), account::id(account), identity, reason_hash);
    kyc_proof::destroy_all(approvals);
}
