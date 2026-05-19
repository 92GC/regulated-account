module regulated_account::policy_events;

use std::type_name;
use regulated_account::keys::{HolderKey, IdentityKey};
use sui::event;

public struct FreezeEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    frozen: bool,
    reason_hash: vector<u8>,
}

public struct KycUpdatedEvent has copy, drop {
    asset_id: ID,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
}

public struct MaxSupplyUpdatedEvent has copy, drop {
    asset_id: ID,
    max_supply: Option<u64>,
    reason_hash: vector<u8>,
}

public struct ShareholderCapsUpdatedEvent has copy, drop {
    asset_id: ID,
    max_shareholders: Option<u64>,
    reason_hash: vector<u8>,
}

public struct ShareholderCountUpdatedEvent has copy, drop {
    asset_id: ID,
    identity: IdentityKey,
    identity_positive_accounts: u64,
    total_shareholders: u64,
}

public struct ComplianceModeUpdatedEvent has copy, drop {
    asset_id: ID,
    mode: u8,
    reason_hash: vector<u8>,
}

public struct ComplianceModeLockedEvent has copy, drop {
    asset_id: ID,
    reason_hash: vector<u8>,
}

public struct PauseEvent has copy, drop {
    asset_id: ID,
    paused: bool,
    reason_hash: vector<u8>,
}

public struct DefaultAccountStateUpdatedEvent has copy, drop {
    asset_id: ID,
    frozen: bool,
    reason_hash: vector<u8>,
}

public struct WitnessAuthorizationUpdatedEvent has copy, drop {
    asset_id: ID,
    witness: type_name::TypeName,
    active: bool,
}

public struct KycSourceUpdatedEvent has copy, drop {
    asset_id: ID,
    source_type: type_name::TypeName,
    registry_id: ID,
    trusted: bool,
    required: bool,
    reason_hash: vector<u8>,
}

public struct AccountFlagsUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    memo_required: bool,
    allow_public_credits: bool,
    reason_hash: vector<u8>,
}

public struct LockedBalanceUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    locked_balance: u64,
    reason_hash: vector<u8>,
}

public struct HolderLockedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    reason_hash: vector<u8>,
}

public struct HolderUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    holder: HolderKey,
    reason_hash: vector<u8>,
}

public struct IdentityUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    identity: IdentityKey,
    reason_hash: vector<u8>,
}

public struct MintClosedEvent has copy, drop {
    asset_id: ID,
    reason_hash: vector<u8>,
}

public(package) fun emit_freeze(
    asset_id: ID,
    account_id: ID,
    frozen: bool,
    reason_hash: vector<u8>,
) {
    event::emit(FreezeEvent { asset_id, account_id, frozen, reason_hash });
}

public(package) fun emit_kyc_updated(
    asset_id: ID,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    event::emit(KycUpdatedEvent {
        asset_id,
        identity,
        status,
        expires_ms,
        external_ref_hash,
    });
}

public(package) fun emit_max_supply_updated(
    asset_id: ID,
    max_supply: Option<u64>,
    reason_hash: vector<u8>,
) {
    event::emit(MaxSupplyUpdatedEvent { asset_id, max_supply, reason_hash });
}

public(package) fun emit_shareholder_caps_updated(
    asset_id: ID,
    max_shareholders: Option<u64>,
    reason_hash: vector<u8>,
) {
    event::emit(ShareholderCapsUpdatedEvent { asset_id, max_shareholders, reason_hash });
}

public(package) fun emit_shareholder_count_updated(
    asset_id: ID,
    identity: IdentityKey,
    identity_positive_accounts: u64,
    total_shareholders: u64,
) {
    event::emit(ShareholderCountUpdatedEvent {
        asset_id,
        identity,
        identity_positive_accounts,
        total_shareholders,
    });
}

public(package) fun emit_compliance_mode_updated(
    asset_id: ID,
    mode: u8,
    reason_hash: vector<u8>,
) {
    event::emit(ComplianceModeUpdatedEvent { asset_id, mode, reason_hash });
}

public(package) fun emit_compliance_mode_locked(asset_id: ID, reason_hash: vector<u8>) {
    event::emit(ComplianceModeLockedEvent { asset_id, reason_hash });
}

public(package) fun emit_pause(asset_id: ID, paused: bool, reason_hash: vector<u8>) {
    event::emit(PauseEvent { asset_id, paused, reason_hash });
}

public(package) fun emit_default_account_state_updated(
    asset_id: ID,
    frozen: bool,
    reason_hash: vector<u8>,
) {
    event::emit(DefaultAccountStateUpdatedEvent { asset_id, frozen, reason_hash });
}

public(package) fun emit_witness_authorization_updated(
    asset_id: ID,
    witness: type_name::TypeName,
    active: bool,
) {
    event::emit(WitnessAuthorizationUpdatedEvent { asset_id, witness, active });
}

public(package) fun emit_kyc_source_updated(
    asset_id: ID,
    source_type: type_name::TypeName,
    registry_id: ID,
    trusted: bool,
    required: bool,
    reason_hash: vector<u8>,
) {
    event::emit(KycSourceUpdatedEvent {
        asset_id,
        source_type,
        registry_id,
        trusted,
        required,
        reason_hash,
    });
}

public(package) fun emit_account_flags_updated(
    asset_id: ID,
    account_id: ID,
    memo_required: bool,
    allow_public_credits: bool,
    reason_hash: vector<u8>,
) {
    event::emit(AccountFlagsUpdatedEvent {
        asset_id,
        account_id,
        memo_required,
        allow_public_credits,
        reason_hash,
    });
}

public(package) fun emit_locked_balance_updated(
    asset_id: ID,
    account_id: ID,
    locked_balance: u64,
    reason_hash: vector<u8>,
) {
    event::emit(LockedBalanceUpdatedEvent { asset_id, account_id, locked_balance, reason_hash });
}

public(package) fun emit_holder_locked(asset_id: ID, account_id: ID, reason_hash: vector<u8>) {
    event::emit(HolderLockedEvent { asset_id, account_id, reason_hash });
}

public(package) fun emit_holder_updated(
    asset_id: ID,
    account_id: ID,
    holder: HolderKey,
    reason_hash: vector<u8>,
) {
    event::emit(HolderUpdatedEvent { asset_id, account_id, holder, reason_hash });
}

public(package) fun emit_identity_updated(
    asset_id: ID,
    account_id: ID,
    identity: IdentityKey,
    reason_hash: vector<u8>,
) {
    event::emit(IdentityUpdatedEvent { asset_id, account_id, identity, reason_hash });
}

public(package) fun emit_mint_closed(asset_id: ID, reason_hash: vector<u8>) {
    event::emit(MintClosedEvent { asset_id, reason_hash });
}
