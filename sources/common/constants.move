/// Protocol constants for the regulated-account framework.
///
/// Move constants are module-local, so this module exposes shared protocol knobs
/// through functions that can be referenced consistently across the package.
module regulated_account::constants;

// === Compliance Modes ===

public(package) fun mode_allowlist(): u8 { 0 }
public(package) fun mode_denylist(): u8 { 1 }
public(package) fun mode_open(): u8 { 2 }

// === Holder/Identity Kinds ===

public(package) fun holder_address_kind(): u8 { 0 }
public(package) fun holder_package_kind(): u8 { 1 }
public(package) fun identity_address_kind(): u8 { 0 }
public(package) fun identity_external_kind(): u8 { 1 }

// === Authority Kinds ===

public(package) fun authority_owner(): u8 { 0 }
public(package) fun authority_package(): u8 { 1 }

// === KYC Statuses ===

public(package) fun kyc_unknown(): u8 { 0 }
public(package) fun kyc_approved(): u8 { 1 }
public(package) fun kyc_denied(): u8 { 2 }
public(package) fun kyc_pending(): u8 { 3 }
public(package) fun kyc_expired(): u8 { 4 }
public(package) fun kyc_exempt(): u8 { 5 }
public(package) fun kyc_divest_only(): u8 { 6 }

// === Size Limits ===

public(package) fun max_memo_bytes(): u64 { 1024 }
public(package) fun max_external_ref_hash_bytes(): u64 { 128 }
public(package) fun max_symbol_bytes(): u64 { 32 }
public(package) fun max_name_bytes(): u64 { 128 }
public(package) fun max_description_bytes(): u64 { 2048 }
public(package) fun max_icon_url_bytes(): u64 { 512 }

// === Policy Limits ===

public(package) fun max_kyc_approvals(): u64 { 128 }
public(package) fun max_trusted_kyc_sources(): u64 { 128 }
public(package) fun max_required_kyc_sources(): u64 { 32 }
