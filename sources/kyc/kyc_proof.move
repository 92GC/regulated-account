module regulated_account::kyc_proof;

use std::type_name;
use regulated_account::keys::IdentityKey;

public struct KycSourceKey has copy, drop, store {
    source_type: type_name::TypeName,
    registry_id: ID,
}

public struct KycSourceConfig has copy, drop, store {
    source: KycSourceKey,
    required: bool,
}

public struct KycApproval<phantom T> {
    asset_id: ID,
    identity: IdentityKey,
    source: KycSourceKey,
    expires_ms: u64,
}

public fun source_type(source: KycSourceKey): type_name::TypeName {
    source.source_type
}

public fun registry_id(source: KycSourceKey): ID {
    source.registry_id
}

public fun source_config(source: KycSourceKey, required: bool): KycSourceConfig {
    KycSourceConfig { source, required }
}

public fun config_source(config: KycSourceConfig): KycSourceKey {
    config.source
}

public fun config_required(config: KycSourceConfig): bool {
    config.required
}

public fun approval_identity<T>(approval: &KycApproval<T>): IdentityKey {
    approval.identity
}

public fun approval_source<T>(approval: &KycApproval<T>): KycSourceKey {
    approval.source
}

public fun approval_expires_ms<T>(approval: &KycApproval<T>): u64 {
    approval.expires_ms
}

public fun destroy<T>(approval: KycApproval<T>) {
    let KycApproval { asset_id: _, identity: _, source: _, expires_ms: _ } = approval;
}

public fun destroy_all<T>(mut approvals: vector<KycApproval<T>>) {
    while (!approvals.is_empty()) {
        destroy(approvals.pop_back());
    };
    approvals.destroy_empty();
}

public fun source_key<R>(registry_id: ID): KycSourceKey {
    KycSourceKey { source_type: type_name::with_original_ids<R>(), registry_id }
}

public(package) fun new<T>(
    asset_id: ID,
    identity: IdentityKey,
    source: KycSourceKey,
    expires_ms: u64,
): KycApproval<T> {
    KycApproval { asset_id, identity, source, expires_ms }
}

public(package) fun valid_for<T>(
    approval: &KycApproval<T>,
    asset_id: ID,
    identity: IdentityKey,
    now_ms: &Option<u64>,
): bool {
    approval.asset_id == asset_id &&
        approval.identity == identity &&
        time_valid(approval.expires_ms, now_ms)
}

public(package) fun valid_for_source<T>(
    approval: &KycApproval<T>,
    asset_id: ID,
    identity: IdentityKey,
    source: KycSourceKey,
    now_ms: &Option<u64>,
): bool {
    valid_for(approval, asset_id, identity, now_ms) &&
        approval.source == source
}

public(package) fun contains_valid_for_source<T>(
    approvals: &vector<KycApproval<T>>,
    asset_id: ID,
    identity: IdentityKey,
    source: KycSourceKey,
    now_ms: &Option<u64>,
): bool {
    let mut i = 0;
    let len = approvals.length();
    while (i < len) {
        if (valid_for_source(&approvals[i], asset_id, identity, source, now_ms)) {
            return true
        };
        i = i + 1;
    };
    false
}

fun time_valid(expires_ms: u64, now_ms: &Option<u64>): bool {
    if (expires_ms == 0) {
        true
    } else if (now_ms.is_some()) {
        *now_ms.borrow() <= expires_ms
    } else {
        false
    }
}
