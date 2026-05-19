module regulated_account::asset;

use std::type_name;
use regulated_account::amount_math;
use regulated_account::caps::{Self, CloseMintCap, MintCap, PolicyCap};
use regulated_account::policy_events;
use regulated_account::fees::{Self, FeeConfig};
use regulated_account::keys::IdentityKey;
use regulated_account::kyc::{Self, KycRecord};
use regulated_account::shareholders::{Self, Shareholders};
use regulated_account::validation;
use sui::table::{Self, Table};

const MODE_ALLOWLIST: u8 = 0;
const MODE_DENYLIST: u8 = 1;
const MODE_OPEN: u8 = 2;

const EInvalidMode: u64 = 2;
const EIdentityNotAllowed: u64 = 7;
const EPolicyImmutable: u64 = 11;
const EMintClosed: u64 = 12;
const EMaxSupplyExceeded: u64 = 22;
const EInvalidDisplayScale: u64 = 17;
const EAssetPaused: u64 = 18;

/// Shared asset policy and accounting state for regulated account balances of type `T`.
public struct Asset<phantom T> has key {
    id: UID,
    supply: u64,
    max_supply: Option<u64>,
    shareholders: Shareholders,
    display_scale_numerator: u64,
    display_scale_denominator: u64,
    mode: u8,
    mode_mutable: bool,
    mint_closed: bool,
    paused: bool,
    default_account_frozen: bool,
    fee: FeeConfig,
    kyc: Table<IdentityKey, KycRecord>,
    shareholder_accounts: Table<IdentityKey, u64>,
    authorized_witnesses: Table<type_name::TypeName, bool>,
    authorized_packages: Table<address, bool>,
}

public(package) fun new<T>(
    max_supply: Option<u64>,
    mode: u8,
    mode_mutable: bool,
    ctx: &mut TxContext,
): Asset<T> {
    assert_valid_mode(mode);
    Asset {
        id: object::new(ctx),
        supply: 0,
        max_supply,
        shareholders: shareholders::new(ctx),
        display_scale_numerator: 1,
        display_scale_denominator: 1,
        mode,
        mode_mutable,
        mint_closed: false,
        paused: false,
        default_account_frozen: false,
        fee: fees::zero(),
        kyc: table::new(ctx),
        shareholder_accounts: table::new(ctx),
        authorized_witnesses: table::new(ctx),
        authorized_packages: table::new(ctx),
    }
}

public(package) fun share<T>(asset: Asset<T>) {
    transfer::share_object(asset);
}

public fun allowlist_mode(): u8 { MODE_ALLOWLIST }
public fun denylist_mode(): u8 { MODE_DENYLIST }
public fun open_mode(): u8 { MODE_OPEN }

public fun kyc_unknown(): u8 { kyc::unknown() }
public fun kyc_approved(): u8 { kyc::approved() }
public fun kyc_denied(): u8 { kyc::denied() }
public fun kyc_pending(): u8 { kyc::pending() }
public fun kyc_expired(): u8 { kyc::expired() }
public fun kyc_exempt(): u8 { kyc::exempt() }

public fun id<T>(asset: &Asset<T>): ID { object::id(asset) }
public fun supply<T>(asset: &Asset<T>): u64 { asset.supply }
public fun max_supply<T>(asset: &Asset<T>): Option<u64> { asset.max_supply }
public fun total_shareholders<T>(asset: &Asset<T>): u64 { shareholders::total(&asset.shareholders) }
public fun shareholder_cap<T>(asset: &Asset<T>): Option<u64> { shareholders::cap(&asset.shareholders) }
public fun min_positive_balance<T>(asset: &Asset<T>): u64 {
    shareholders::min_positive_balance(&asset.shareholders)
}
public fun paused<T>(asset: &Asset<T>): bool { asset.paused }
public fun default_account_frozen<T>(asset: &Asset<T>): bool { asset.default_account_frozen }
public fun mode<T>(asset: &Asset<T>): u8 { asset.mode }

public fun identity_positive_account_count<T>(asset: &Asset<T>, identity: IdentityKey): u64 {
    shareholders::identity_positive_account_count(&asset.shareholders, identity)
}

public fun has_kyc<T>(asset: &Asset<T>, identity: IdentityKey): bool {
    asset.kyc.contains(identity)
}

public fun kyc_status<T>(asset: &Asset<T>, identity: IdentityKey): u8 {
    if (asset.kyc.contains(identity)) {
        kyc::status(asset.kyc.borrow(identity))
    } else {
        kyc::unknown()
    }
}

public fun kyc_expires_ms<T>(asset: &Asset<T>, identity: IdentityKey): u64 {
    if (asset.kyc.contains(identity)) {
        kyc::expires_ms(asset.kyc.borrow(identity))
    } else {
        0
    }
}

public fun kyc_external_ref_hash<T>(asset: &Asset<T>, identity: IdentityKey): vector<u8> {
    if (asset.kyc.contains(identity)) {
        kyc::external_ref_hash(asset.kyc.borrow(identity))
    } else {
        vector[]
    }
}

public fun authorized_package<T>(asset: &Asset<T>, package_addr: address): bool {
    asset.authorized_packages.contains(package_addr) &&
        *asset.authorized_packages.borrow(package_addr)
}

public fun authorized_witness<T, W: drop>(asset: &Asset<T>): bool {
    let witness = type_name::with_original_ids<W>();
    asset.authorized_witnesses.contains(witness) &&
        *asset.authorized_witnesses.borrow(witness)
}

public fun display_scale<T>(asset: &Asset<T>): (u64, u64) {
    (asset.display_scale_numerator, asset.display_scale_denominator)
}

public fun display_supply<T>(asset: &Asset<T>): Option<u64> {
    checked_display_supply(asset)
}

public fun set_max_supply<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    max_supply: Option<u64>,
    reason_hash: vector<u8>,
) {
    caps::assert_mint(id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    set_max_supply_internal(asset, max_supply);
    policy_events::emit_max_supply_updated(id(asset), max_supply, reason_hash);
}

public fun set_display_scale<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    numerator: u64,
    denominator: u64,
) {
    caps::assert_policy(id(asset), cap);
    set_display_scale_internal(asset, numerator, denominator);
    policy_events::emit_display_scale_updated(id(asset), numerator, denominator);
}

public fun close_mint<T>(asset: &mut Asset<T>, cap: &CloseMintCap<T>, reason_hash: vector<u8>) {
    caps::assert_close_mint(id(asset), cap);
    validation::assert_external_ref_hash(&reason_hash);
    close_mint_internal(asset);
    policy_events::emit_mint_closed(id(asset), reason_hash);
}

public(package) fun fee<T>(asset: &Asset<T>): &FeeConfig {
    &asset.fee
}

public(package) fun assert_valid_mode(mode: u8) {
    assert!(mode == MODE_ALLOWLIST || mode == MODE_DENYLIST || mode == MODE_OPEN, EInvalidMode);
}

public(package) fun assert_valid_kyc_status(status: u8) {
    kyc::assert_valid_status(status);
}

public(package) fun assert_mint_open<T>(asset: &Asset<T>) {
    assert!(!asset.mint_closed, EMintClosed);
}

public(package) fun assert_not_paused<T>(asset: &Asset<T>) {
    assert!(!asset.paused, EAssetPaused);
}

public(package) fun increase_supply<T>(asset: &mut Asset<T>, amount: u64): u64 {
    let new_supply = amount_math::checked_add(asset.supply, amount);
    assert_max_supply(asset.max_supply, new_supply);
    asset.supply = new_supply;
    new_supply
}

public(package) fun decrease_supply<T>(asset: &mut Asset<T>, amount: u64) {
    asset.supply = asset.supply - amount;
}

public(package) fun assert_display_supply<T>(asset: &Asset<T>, supply: u64) {
    amount_math::assert_scalable_u64(
        supply,
        asset.display_scale_numerator,
        asset.display_scale_denominator,
    );
}

public(package) fun checked_display_balance<T>(asset: &Asset<T>, balance: u64): Option<u64> {
    amount_math::checked_scaled_u64(
        balance,
        asset.display_scale_numerator,
        asset.display_scale_denominator,
    )
}

public(package) fun checked_display_supply<T>(asset: &Asset<T>): Option<u64> {
    checked_display_balance(asset, asset.supply)
}

public(package) fun set_kyc<T>(
    asset: &mut Asset<T>,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    let record = kyc::new(status, expires_ms, external_ref_hash);
    if (asset.kyc.contains(identity)) {
        *asset.kyc.borrow_mut(identity) = record;
    } else {
        asset.kyc.add(identity, record);
    };
}

public(package) fun remove_kyc<T>(asset: &mut Asset<T>, identity: IdentityKey): bool {
    if (asset.kyc.contains(identity)) {
        let _removed = asset.kyc.remove(identity);
        true
    } else {
        false
    }
}

public(package) fun assert_identity_allowed<T>(
    asset: &Asset<T>,
    identity: IdentityKey,
    now_ms: &Option<u64>,
) {
    let allowed = if (asset.mode == MODE_OPEN) {
        true
    } else if (asset.mode == MODE_ALLOWLIST) {
        asset.kyc.contains(identity) &&
            kyc::approved_now(asset.kyc.borrow(identity), now_ms)
    } else {
        !asset.kyc.contains(identity) ||
            kyc::not_denied_now(asset.kyc.borrow(identity), now_ms)
    };
    assert!(allowed, EIdentityNotAllowed);
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

public(package) fun set_min_positive_balance<T>(asset: &mut Asset<T>, min_balance: u64) {
    shareholders::set_min_positive_balance(&mut asset.shareholders, min_balance);
}

public(package) fun set_fee<T>(asset: &mut Asset<T>, fee: FeeConfig) {
    asset.fee = fee;
}

public(package) fun clear_fee<T>(asset: &mut Asset<T>) {
    asset.fee = fees::zero();
}

public(package) fun set_paused<T>(asset: &mut Asset<T>, paused: bool) {
    asset.paused = paused;
}

public(package) fun set_default_account_frozen<T>(asset: &mut Asset<T>, frozen: bool) {
    asset.default_account_frozen = frozen;
}

public(package) fun set_display_scale_internal<T>(
    asset: &mut Asset<T>,
    numerator: u64,
    denominator: u64,
) {
    assert!(numerator > 0 && denominator > 0, EInvalidDisplayScale);
    amount_math::assert_scalable_u64(asset.supply, numerator, denominator);
    asset.display_scale_numerator = numerator;
    asset.display_scale_denominator = denominator;
}

#[test_only]
public(package) fun set_display_scale_for_testing<T>(
    asset: &mut Asset<T>,
    numerator: u64,
    denominator: u64,
) {
    asset.display_scale_numerator = numerator;
    asset.display_scale_denominator = denominator;
}

public(package) fun close_mint_internal<T>(asset: &mut Asset<T>) {
    asset.mint_closed = true;
}

public(package) fun authorize_witness<T, W: drop>(asset: &mut Asset<T>): type_name::TypeName {
    let witness = type_name::with_original_ids<W>();
    if (asset.authorized_witnesses.contains(witness)) {
        *asset.authorized_witnesses.borrow_mut(witness) = true;
    } else {
        asset.authorized_witnesses.add(witness, true);
    };
    witness
}

public(package) fun deauthorize_witness<T, W: drop>(asset: &mut Asset<T>): type_name::TypeName {
    let witness = type_name::with_original_ids<W>();
    if (asset.authorized_witnesses.contains(witness)) {
        let _removed = asset.authorized_witnesses.remove(witness);
    };
    witness
}

public(package) fun authorize_package<T>(asset: &mut Asset<T>, package_addr: address) {
    if (asset.authorized_packages.contains(package_addr)) {
        *asset.authorized_packages.borrow_mut(package_addr) = true;
    } else {
        asset.authorized_packages.add(package_addr, true);
    };
}

public(package) fun deauthorize_package<T>(asset: &mut Asset<T>, package_addr: address) {
    if (asset.authorized_packages.contains(package_addr)) {
        let _removed = asset.authorized_packages.remove(package_addr);
    };
}

public(package) fun package_authorized<T>(asset: &Asset<T>, package_addr: address): bool {
    authorized_package(asset, package_addr)
}

public(package) fun witness_authorized<T>(
    asset: &Asset<T>,
    witness: type_name::TypeName,
): bool {
    asset.authorized_witnesses.contains(witness) &&
        *asset.authorized_witnesses.borrow(witness)
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

public(package) fun assert_min_positive_balance<T>(asset: &Asset<T>, balance: u64) {
    shareholders::assert_min_positive_balance(&asset.shareholders, balance);
}

fun assert_max_supply(max_supply: Option<u64>, supply: u64) {
    if (max_supply.is_some()) {
        assert!(supply <= *max_supply.borrow(), EMaxSupplyExceeded);
    };
}
