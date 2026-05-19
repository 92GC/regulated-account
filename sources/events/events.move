module regulated_account::events;

use std::string::String;
use std::type_name;
use regulated_account::keys::{HolderKey, IdentityKey};
use sui::event;

public struct AssetCreated has copy, drop {
    asset_id: ID,
    metadata_id: ID,
    receipt_type: type_name::TypeName,
    issuer: address,
    mode: u8,
    max_supply: Option<u64>,
}

public struct AccountCreated has copy, drop {
    asset_id: ID,
    account_id: ID,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_id: Option<ID>,
}

public struct TransferEvent has copy, drop {
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount: u64,
    memo: vector<u8>,
}

public struct MintEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    amount: u64,
}

public struct RestrictedMintEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
}

public struct BurnEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    amount: u64,
    admin_burn: bool,
    reason_hash: vector<u8>,
}

public struct ClawbackEvent has copy, drop {
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount: u64,
    reason_hash: vector<u8>,
}

public struct MetadataUpdatedEvent has copy, drop {
    asset_id: ID,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
}

public struct MetadataDecimalsUpdatedEvent has copy, drop {
    asset_id: ID,
    decimals: u8,
}

public struct MetadataRegisteredEvent has copy, drop {
    receipt_type: type_name::TypeName,
    metadata_id: ID,
    asset_id: ID,
}

public(package) fun emit_asset_created(
    asset_id: ID,
    metadata_id: ID,
    receipt_type: type_name::TypeName,
    issuer: address,
    mode: u8,
    max_supply: Option<u64>,
) {
    event::emit(AssetCreated {
        asset_id,
        metadata_id,
        receipt_type,
        issuer,
        mode,
        max_supply,
    });
}

public(package) fun emit_account_created(
    asset_id: ID,
    account_id: ID,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_id: Option<ID>,
) {
    event::emit(AccountCreated { asset_id, account_id, holder, identity, receipt_id });
}

public(package) fun emit_transfer(
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount: u64,
    memo: vector<u8>,
) {
    event::emit(TransferEvent {
        asset_id,
        from_account,
        to_account,
        amount,
        memo,
    });
}

public(package) fun emit_mint(asset_id: ID, account_id: ID, amount: u64) {
    event::emit(MintEvent { asset_id, account_id, amount });
}

public(package) fun emit_restricted_mint(
    asset_id: ID,
    account_id: ID,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
) {
    event::emit(RestrictedMintEvent {
        asset_id,
        account_id,
        amount,
        unlock_ms,
        external_ref_hash,
    });
}

public(package) fun emit_burn(
    asset_id: ID,
    account_id: ID,
    amount: u64,
    admin_burn: bool,
    reason_hash: vector<u8>,
) {
    event::emit(BurnEvent { asset_id, account_id, amount, admin_burn, reason_hash });
}

public(package) fun emit_clawback(
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount: u64,
    reason_hash: vector<u8>,
) {
    event::emit(ClawbackEvent { asset_id, from_account, to_account, amount, reason_hash });
}

public(package) fun emit_metadata_updated(
    asset_id: ID,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
) {
    event::emit(MetadataUpdatedEvent { asset_id, symbol, name, description, icon_url });
}

public(package) fun emit_metadata_decimals_updated(asset_id: ID, decimals: u8) {
    event::emit(MetadataDecimalsUpdatedEvent { asset_id, decimals });
}

public(package) fun emit_metadata_registered(
    receipt_type: type_name::TypeName,
    metadata_id: ID,
    asset_id: ID,
) {
    event::emit(MetadataRegisteredEvent { receipt_type, metadata_id, asset_id });
}
