module regulated_account::kyc_admin;

use regulated_account::asset::{Self, Asset};
use regulated_account::caps::{Self, PolicyCap};
use regulated_account::keys::IdentityKey;
use regulated_account::kyc;
use regulated_account::kyc_proof;
use regulated_account::policy_events;
use regulated_account::validation;

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
        policy_events::emit_kyc_updated(asset::id(asset), identity, kyc::unknown(), 0, vector[]);
    };
}

public fun trust_kyc_source<T, R>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    registry_id: ID,
    required: bool,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    let source = asset::trust_kyc_source<T, R>(asset, registry_id, required);
    policy_events::emit_kyc_source_updated(
        asset::id(asset),
        kyc_proof::source_type(source),
        kyc_proof::registry_id(source),
        true,
        required,
        reason_hash,
    );
}

public fun untrust_kyc_source<T, R>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    registry_id: ID,
    reason_hash: vector<u8>,
) {
    caps::assert_policy(asset::id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    let source = asset::untrust_kyc_source<T, R>(asset, registry_id);
    policy_events::emit_kyc_source_updated(
        asset::id(asset),
        kyc_proof::source_type(source),
        kyc_proof::registry_id(source),
        false,
        false,
        reason_hash,
    );
}
