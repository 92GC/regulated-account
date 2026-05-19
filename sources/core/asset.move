module regulated_account::asset;

use std::type_name;
use regulated_account::amount_math;
use regulated_account::authority::{Self, WitnessPolicy};
use regulated_account::constants;
use regulated_account::keys::IdentityKey;
use regulated_account::kyc_policy::{Self, KycPolicy};
use regulated_account::kyc_proof::{KycApproval, KycSourceConfig, KycSourceKey};
use regulated_account::shareholders::{Self, Shareholders};
use sui::table::{Self, Table};

const EInvalidMode: u64 = 2;
const EPolicyImmutable: u64 = 11;
const EMintClosed: u64 = 12;
const EMaxSupplyExceeded: u64 = 22;
const EAssetPaused: u64 = 18;
const EIdentityFrozen: u64 = 6;

/// Shared asset policy and accounting state for regulated account balances of type `T`.
public struct Asset<phantom T> has key {
    id: UID,
    supply: u64,
    max_supply: Option<u64>,
    shareholders: Shareholders,
    mode: u8,
    mode_mutable: bool,
    mint_closed: bool,
    paused: bool,
    default_account_frozen: bool,
    frozen_identities: Table<IdentityKey, bool>,
    kyc_policy: KycPolicy,
    authorized_witnesses: WitnessPolicy,
}

public(package) fun new<T>(
    max_supply: Option<u64>,
    mode: u8,
    mode_mutable: bool,
    kyc_sources: vector<KycSourceConfig>,
    ctx: &mut TxContext,
): Asset<T> {
    assert_valid_mode(mode);
    Asset {
        id: object::new(ctx),
        supply: 0,
        max_supply,
        shareholders: shareholders::new(ctx),
        mode,
        mode_mutable,
        mint_closed: false,
        paused: false,
        default_account_frozen: false,
        frozen_identities: table::new(ctx),
        kyc_policy: kyc_policy::new(kyc_sources, ctx),
        authorized_witnesses: authority::new_witness_policy(ctx),
    }
}

public(package) fun share<T>(asset: Asset<T>) {
    transfer::share_object(asset);
}

public fun allowlist_mode(): u8 { constants::mode_allowlist() }
public fun denylist_mode(): u8 { constants::mode_denylist() }
public fun open_mode(): u8 { constants::mode_open() }

public fun id<T>(asset: &Asset<T>): ID { object::id(asset) }
public fun supply<T>(asset: &Asset<T>): u64 { asset.supply }
public fun max_supply<T>(asset: &Asset<T>): Option<u64> { asset.max_supply }
public fun total_shareholders<T>(asset: &Asset<T>): u64 { shareholders::total(&asset.shareholders) }
public fun shareholder_cap<T>(asset: &Asset<T>): Option<u64> { shareholders::cap(&asset.shareholders) }
public fun paused<T>(asset: &Asset<T>): bool { asset.paused }
public fun default_account_frozen<T>(asset: &Asset<T>): bool { asset.default_account_frozen }
public fun mode<T>(asset: &Asset<T>): u8 { asset.mode }
public fun identity_frozen<T>(asset: &Asset<T>, identity: IdentityKey): bool {
    asset.frozen_identities.contains(identity)
}

public fun identity_positive_account_count<T>(asset: &Asset<T>, identity: IdentityKey): u64 {
    shareholders::identity_positive_account_count(&asset.shareholders, identity)
}

public fun has_kyc<T>(asset: &Asset<T>, identity: IdentityKey): bool {
    kyc_policy::has_kyc(&asset.kyc_policy, identity)
}

public fun kyc_status<T>(asset: &Asset<T>, identity: IdentityKey): u8 {
    kyc_policy::kyc_status(&asset.kyc_policy, identity)
}

public fun kyc_expires_ms<T>(asset: &Asset<T>, identity: IdentityKey): u64 {
    kyc_policy::kyc_expires_ms(&asset.kyc_policy, identity)
}

public fun kyc_external_ref_hash<T>(asset: &Asset<T>, identity: IdentityKey): vector<u8> {
    kyc_policy::kyc_external_ref_hash(&asset.kyc_policy, identity)
}

public fun authorized_witness<T, W: drop>(asset: &Asset<T>): bool {
    authority::authorized_witness<W>(&asset.authorized_witnesses)
}

public fun trusted_kyc_source<T, R>(asset: &Asset<T>, registry_id: ID): bool {
    kyc_policy::trusted_source<R>(&asset.kyc_policy, registry_id)
}

public fun required_kyc_source<T, R>(asset: &Asset<T>, registry_id: ID): bool {
    kyc_policy::required_source<R>(&asset.kyc_policy, registry_id)
}

public fun required_kyc_source_count<T>(asset: &Asset<T>): u64 {
    kyc_policy::required_source_count(&asset.kyc_policy)
}

public fun trusted_kyc_source_count<T>(asset: &Asset<T>): u64 {
    kyc_policy::trusted_source_count(&asset.kyc_policy)
}

public(package) fun assert_valid_mode(mode: u8) {
    assert!(
        mode == constants::mode_allowlist() ||
            mode == constants::mode_denylist() ||
            mode == constants::mode_open(),
        EInvalidMode,
    );
}

public(package) fun assert_mint_open<T>(asset: &Asset<T>) {
    assert!(!asset.mint_closed, EMintClosed);
}

public(package) fun assert_not_paused<T>(asset: &Asset<T>) {
    assert!(!asset.paused, EAssetPaused);
}

public(package) fun assert_identity_not_frozen<T>(asset: &Asset<T>, identity: IdentityKey) {
    assert!(!identity_frozen(asset, identity), EIdentityFrozen);
}

public(package) fun increase_supply<T>(asset: &mut Asset<T>, amount: u64): u64 {
    let new_supply = amount_math::checked_add(asset.supply, amount);
    assert_max_supply(asset.max_supply, new_supply);
    asset.supply = new_supply;
    new_supply
}

public(package) fun decrease_supply<T>(asset: &mut Asset<T>, amount: u64) {
    asset.supply = amount_math::checked_sub(asset.supply, amount);
}

public(package) fun set_kyc<T>(
    asset: &mut Asset<T>,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    kyc_policy::set_kyc(&mut asset.kyc_policy, identity, status, expires_ms, external_ref_hash);
}

public(package) fun remove_kyc<T>(asset: &mut Asset<T>, identity: IdentityKey): bool {
    kyc_policy::remove_kyc(&mut asset.kyc_policy, identity)
}

public(package) fun assert_identity_credit_allowed_with_approvals<T>(
    asset: &Asset<T>,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    kyc_policy::assert_identity_credit_allowed_with_approvals(
        &asset.kyc_policy,
        id(asset),
        asset.mode == constants::mode_allowlist(),
        identity,
        now_ms,
        approvals,
    );
}

public(package) fun assert_identity_debit_allowed_with_approvals<T>(
    asset: &Asset<T>,
    identity: IdentityKey,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    kyc_policy::assert_identity_debit_allowed_with_approvals(
        &asset.kyc_policy,
        id(asset),
        asset.mode == constants::mode_allowlist(),
        identity,
        now_ms,
        approvals,
    );
}

public(package) fun set_mode<T>(asset: &mut Asset<T>, mode: u8) {
    assert!(asset.mode_mutable, EPolicyImmutable);
    assert_valid_mode(mode);
    asset.mode = mode;
}

public(package) fun lock_mode<T>(asset: &mut Asset<T>) {
    asset.mode_mutable = false;
}

public(package) fun set_max_supply_internal<T>(asset: &mut Asset<T>, max_supply: Option<u64>) {
    if (max_supply.is_some()) {
        assert!(*max_supply.borrow() >= asset.supply, EMaxSupplyExceeded);
    };
    asset.max_supply = max_supply;
}

public(package) fun set_shareholder_cap<T>(
    asset: &mut Asset<T>,
    max_shareholders: Option<u64>,
) {
    shareholders::set_cap(&mut asset.shareholders, max_shareholders);
}

public(package) fun set_paused<T>(asset: &mut Asset<T>, paused: bool) {
    asset.paused = paused;
}

public(package) fun set_default_account_frozen<T>(asset: &mut Asset<T>, frozen: bool) {
    asset.default_account_frozen = frozen;
}

public(package) fun set_identity_frozen<T>(
    asset: &mut Asset<T>,
    identity: IdentityKey,
    frozen: bool,
) {
    if (frozen) {
        if (asset.frozen_identities.contains(identity)) {
            *asset.frozen_identities.borrow_mut(identity) = true;
        } else {
            asset.frozen_identities.add(identity, true);
        };
    } else if (asset.frozen_identities.contains(identity)) {
        let _removed = asset.frozen_identities.remove(identity);
    };
}

public(package) fun trust_kyc_source<T, R>(
    asset: &mut Asset<T>,
    registry_id: ID,
    required: bool,
): KycSourceKey {
    kyc_policy::trust_source<R>(&mut asset.kyc_policy, registry_id, required)
}

public(package) fun trust_kyc_source_key<T>(
    asset: &mut Asset<T>,
    source: KycSourceKey,
    required: bool,
) {
    kyc_policy::trust_source_key(&mut asset.kyc_policy, source, required);
}

public(package) fun untrust_kyc_source<T, R>(
    asset: &mut Asset<T>,
    registry_id: ID,
): KycSourceKey {
    kyc_policy::untrust_source<R>(&mut asset.kyc_policy, registry_id)
}

public(package) fun close_mint_internal<T>(asset: &mut Asset<T>) {
    asset.mint_closed = true;
}

public(package) fun authorize_witness<T, W: drop>(asset: &mut Asset<T>): type_name::TypeName {
    authority::authorize_witness<W>(&mut asset.authorized_witnesses)
}

public(package) fun deauthorize_witness<T, W: drop>(asset: &mut Asset<T>): type_name::TypeName {
    authority::deauthorize_witness<W>(&mut asset.authorized_witnesses)
}

public(package) fun witness_authorized<T>(
    asset: &Asset<T>,
    witness: type_name::TypeName,
): bool {
    authority::witness_authorized(&asset.authorized_witnesses, witness)
}

public(package) fun register_positive_account<T>(asset: &mut Asset<T>, identity: IdentityKey) {
    shareholders::register(object::id(asset), &mut asset.shareholders, identity);
}

public(package) fun unregister_positive_account<T>(asset: &mut Asset<T>, identity: IdentityKey) {
    shareholders::unregister(object::id(asset), &mut asset.shareholders, identity);
}

public(package) fun transfer_positive_account_identity<T>(
    asset: &mut Asset<T>,
    previous_identity: IdentityKey,
    identity: IdentityKey,
) {
    shareholders::transfer_identity(object::id(asset), &mut asset.shareholders, previous_identity, identity);
}

fun assert_max_supply(max_supply: Option<u64>, supply: u64) {
    if (max_supply.is_some()) {
        assert!(supply <= *max_supply.borrow(), EMaxSupplyExceeded);
    };
}
