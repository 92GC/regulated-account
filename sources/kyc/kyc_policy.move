module regulated_account::kyc_policy;

use regulated_account::constants;
use regulated_account::keys::IdentityKey;
use regulated_account::kyc::{Self, KycRecord};
use regulated_account::kyc_proof::{Self, KycApproval, KycSourceConfig, KycSourceKey};
use sui::table::{Self, Table};

const EIdentityNotAllowed: u64 = 7;
const EKycSourceLimit: u64 = 35;
const EKycApprovalLimit: u64 = 36;

public struct KycPolicy has store {
    records: Table<IdentityKey, KycRecord>,
    trusted_sources: Table<KycSourceKey, bool>,
    trusted_source_count: u64,
    required_sources: vector<KycSourceKey>,
}

public(package) fun new(
    configs: vector<KycSourceConfig>,
    ctx: &mut TxContext,
): KycPolicy {
    let mut policy = KycPolicy {
        records: table::new(ctx),
        trusted_sources: table::new(ctx),
        trusted_source_count: 0,
        required_sources: vector[],
    };
    add_configs(&mut policy, configs);
    policy
}

public(package) fun has_kyc(policy: &KycPolicy, identity: IdentityKey): bool {
    policy.records.contains(identity)
}

public(package) fun kyc_status(policy: &KycPolicy, identity: IdentityKey): u8 {
    if (policy.records.contains(identity)) {
        kyc::status(policy.records.borrow(identity))
    } else {
        kyc::unknown()
    }
}

public(package) fun kyc_expires_ms(policy: &KycPolicy, identity: IdentityKey): u64 {
    if (policy.records.contains(identity)) {
        kyc::expires_ms(policy.records.borrow(identity))
    } else {
        0
    }
}

public(package) fun kyc_external_ref_hash(policy: &KycPolicy, identity: IdentityKey): vector<u8> {
    if (policy.records.contains(identity)) {
        kyc::external_ref_hash(policy.records.borrow(identity))
    } else {
        vector[]
    }
}

public(package) fun trusted_source<R>(policy: &KycPolicy, registry_id: ID): bool {
    trusted_source_key(policy, kyc_proof::source_key<R>(registry_id))
}

public(package) fun required_source<R>(policy: &KycPolicy, registry_id: ID): bool {
    required_source_key(policy, kyc_proof::source_key<R>(registry_id))
}

public(package) fun required_source_count(policy: &KycPolicy): u64 {
    policy.required_sources.length()
}

public(package) fun trusted_source_count(policy: &KycPolicy): u64 {
    policy.trusted_source_count
}

public(package) fun set_kyc(
    policy: &mut KycPolicy,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    let record = kyc::new(status, expires_ms, external_ref_hash);
    if (policy.records.contains(identity)) {
        *policy.records.borrow_mut(identity) = record;
    } else {
        policy.records.add(identity, record);
    };
}

public(package) fun remove_kyc(policy: &mut KycPolicy, identity: IdentityKey): bool {
    if (policy.records.contains(identity)) {
        let _removed = policy.records.remove(identity);
        true
    } else {
        false
    }
}

public(package) fun assert_identity_credit_allowed(
    policy: &KycPolicy,
    is_open: bool,
    is_allowlist: bool,
    identity: IdentityKey,
    now_ms: &Option<u64>,
) {
    assert!(
        native_or_default_credit_allowed(policy, is_open, is_allowlist, identity, now_ms) &&
            policy.required_sources.is_empty(),
        EIdentityNotAllowed,
    );
}

public(package) fun assert_identity_credit_allowed_with_approvals<T>(
    policy: &KycPolicy,
    asset_id: ID,
    is_allowlist: bool,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    assert_direction_allowed_with_approvals(
        policy,
        asset_id,
        is_allowlist,
        identity,
        now_ms,
        approvals,
        true,
    );
}

public(package) fun assert_identity_debit_allowed_with_approvals<T>(
    policy: &KycPolicy,
    asset_id: ID,
    is_allowlist: bool,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    assert_direction_allowed_with_approvals(
        policy,
        asset_id,
        is_allowlist,
        identity,
        now_ms,
        approvals,
        false,
    );
}

fun assert_direction_allowed_with_approvals<T>(
    policy: &KycPolicy,
    asset_id: ID,
    is_allowlist: bool,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
    is_credit: bool,
) {
    assert!(approvals.length() <= constants::max_kyc_approvals(), EKycApprovalLimit);
    let native_decision = native_direction_decision(policy, identity, now_ms, is_credit);
    let mode_allowed = if (native_decision.is_some()) {
        *native_decision.borrow()
    } else if (is_allowlist) {
        external_identity_allowed(policy, asset_id, identity, now_ms, approvals)
    } else {
        true
    };
    assert!(mode_allowed, EIdentityNotAllowed);
    if (!policy.required_sources.is_empty()) {
        assert!(
            required_sources_satisfied(policy, asset_id, identity, now_ms, approvals),
            EIdentityNotAllowed,
        );
    };
}

public(package) fun trust_source<R>(
    policy: &mut KycPolicy,
    registry_id: ID,
    required: bool,
): KycSourceKey {
    let source = kyc_proof::source_key<R>(registry_id);
    trust_source_key(policy, source, required);
    source
}

public(package) fun trust_source_key(
    policy: &mut KycPolicy,
    source: KycSourceKey,
    required: bool,
) {
    if (policy.trusted_sources.contains(source)) {
        *policy.trusted_sources.borrow_mut(source) = required;
    } else {
        assert!(policy.trusted_source_count < constants::max_trusted_kyc_sources(), EKycSourceLimit);
        policy.trusted_sources.add(source, required);
        policy.trusted_source_count = policy.trusted_source_count + 1;
    };
    set_required_source(policy, source, required);
}

public(package) fun untrust_source<R>(
    policy: &mut KycPolicy,
    registry_id: ID,
): KycSourceKey {
    let source = kyc_proof::source_key<R>(registry_id);
    if (policy.trusted_sources.contains(source)) {
        let _removed = policy.trusted_sources.remove(source);
        policy.trusted_source_count = policy.trusted_source_count - 1;
    };
    set_required_source(policy, source, false);
    source
}

fun trusted_source_key(policy: &KycPolicy, source: KycSourceKey): bool {
    policy.trusted_sources.contains(source)
}

fun add_configs(policy: &mut KycPolicy, configs: vector<KycSourceConfig>) {
    let mut i = 0;
    let len = configs.length();
    while (i < len) {
        let config = configs[i];
        trust_source_key(
            policy,
            kyc_proof::config_source(config),
            kyc_proof::config_required(config),
        );
        i = i + 1;
    };
}

fun required_source_key(policy: &KycPolicy, source: KycSourceKey): bool {
    policy.trusted_sources.contains(source) &&
        *policy.trusted_sources.borrow(source)
}

fun set_required_source(
    policy: &mut KycPolicy,
    source: KycSourceKey,
    required: bool,
) {
    let mut index = 0;
    let mut found = false;
    let len = policy.required_sources.length();
    while (index < len) {
        if (policy.required_sources[index] == source) {
            found = true;
            break
        };
        index = index + 1;
    };
    if (required && !found) {
        assert!(len < constants::max_required_kyc_sources(), EKycSourceLimit);
        policy.required_sources.push_back(source);
    } else if (!required && found) {
        let _removed = policy.required_sources.remove(index);
    };
}

fun native_direction_decision(
    policy: &KycPolicy,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    is_credit: bool,
): Option<bool> {
    if (policy.records.contains(identity)) {
        let record = policy.records.borrow(identity);
        let status = kyc::effective_status(record, now_ms);
        if (status == kyc::unknown()) {
            option::none()
        } else if (is_credit) {
            option::some(kyc::credit_allowed(record, now_ms))
        } else {
            option::some(kyc::debit_allowed(record, now_ms))
        }
    } else {
        option::none()
    }
}

fun native_or_default_credit_allowed(
    policy: &KycPolicy,
    is_open: bool,
    is_allowlist: bool,
    identity: IdentityKey,
    now_ms: &Option<u64>,
): bool {
    let native_decision = native_direction_decision(policy, identity, now_ms, true);
    if (native_decision.is_some()) {
        *native_decision.borrow()
    } else {
        is_open || !is_allowlist
    }
}

fun external_identity_allowed<T>(
    policy: &KycPolicy,
    asset_id: ID,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
): bool {
    let mut i = 0;
    let len = approvals.length();
    while (i < len) {
        let approval = &approvals[i];
        if (kyc_proof::valid_for(approval, asset_id, identity, now_ms)) {
            let source = kyc_proof::approval_source(approval);
            if (trusted_source_key(policy, source)) {
                return true
            };
        };
        i = i + 1;
    };
    false
}

fun required_sources_satisfied<T>(
    policy: &KycPolicy,
    asset_id: ID,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
): bool {
    let mut i = 0;
    let len = policy.required_sources.length();
    while (i < len) {
        if (!kyc_proof::contains_valid_for_source(
            approvals,
            asset_id,
            identity,
            policy.required_sources[i],
            now_ms,
        )) {
            return false
        };
        i = i + 1;
    };
    true
}
