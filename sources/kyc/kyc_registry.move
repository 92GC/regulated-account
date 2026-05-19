module regulated_account::kyc_registry;

use std::type_name;
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, Time};
use regulated_account::keys::IdentityKey;
use regulated_account::kyc::{Self, KycRecord};
use regulated_account::kyc_proof::{Self, KycApproval, KycSourceKey};
use regulated_account::validation;
use sui::event;
use sui::table::{Self, Table};
use sui::types;

const EBadWitness: u64 = 1;
const ECapRegistryMismatch: u64 = 4;
const EIdentityNotApproved: u64 = 7;

public struct KycRegistry<phantom R> has key {
    id: UID,
    records: Table<IdentityKey, KycRecord>,
}

public struct KycRegistryCap<phantom R> has key, store {
    id: UID,
    registry_id: ID,
}

public struct KycRegistryUpdatedEvent has copy, drop {
    registry_id: ID,
    source_type: type_name::TypeName,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
}

public fun create_registry<R: drop>(
    witness: R,
    ctx: &mut TxContext,
): KycRegistryCap<R> {
    assert!(types::is_one_time_witness(&witness), EBadWitness);
    let registry = KycRegistry<R> {
        id: object::new(ctx),
        records: table::new(ctx),
    };
    let registry_id = object::id(&registry);
    transfer::share_object(registry);
    KycRegistryCap { id: object::new(ctx), registry_id }
}

public fun id<R>(registry: &KycRegistry<R>): ID {
    object::id(registry)
}

public fun cap_registry_id<R>(cap: &KycRegistryCap<R>): ID {
    cap.registry_id
}

public fun source<R>(registry: &KycRegistry<R>): KycSourceKey {
    kyc_proof::source_key<R>(object::id(registry))
}

public fun source_from_id<R>(registry_id: ID): KycSourceKey {
    kyc_proof::source_key<R>(registry_id)
}

public fun has_kyc<R>(registry: &KycRegistry<R>, identity: IdentityKey): bool {
    registry.records.contains(identity)
}

public fun kyc_status<R>(registry: &KycRegistry<R>, identity: IdentityKey): u8 {
    if (registry.records.contains(identity)) {
        kyc::status(registry.records.borrow(identity))
    } else {
        kyc::unknown()
    }
}

public fun kyc_expires_ms<R>(registry: &KycRegistry<R>, identity: IdentityKey): u64 {
    if (registry.records.contains(identity)) {
        kyc::expires_ms(registry.records.borrow(identity))
    } else {
        0
    }
}

public fun kyc_external_ref_hash<R>(
    registry: &KycRegistry<R>,
    identity: IdentityKey,
): vector<u8> {
    if (registry.records.contains(identity)) {
        kyc::external_ref_hash(registry.records.borrow(identity))
    } else {
        vector[]
    }
}

public fun set_kyc<R>(
    registry: &mut KycRegistry<R>,
    cap: &KycRegistryCap<R>,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    assert_cap(registry, cap);
    kyc::assert_valid_status(status);
    validation::assert_external_ref_hash(&external_ref_hash);
    let record = kyc::new(status, expires_ms, external_ref_hash);
    if (registry.records.contains(identity)) {
        *registry.records.borrow_mut(identity) = record;
    } else {
        registry.records.add(identity, record);
    };
    emit_kyc_updated<R>(object::id(registry), identity, status, expires_ms, external_ref_hash);
}

public fun remove_kyc<R>(
    registry: &mut KycRegistry<R>,
    cap: &KycRegistryCap<R>,
    identity: IdentityKey,
): bool {
    assert_cap(registry, cap);
    if (registry.records.contains(identity)) {
        let _removed = registry.records.remove(identity);
        emit_kyc_updated<R>(object::id(registry), identity, kyc::unknown(), 0, vector[]);
        true
    } else {
        false
    }
}

public fun approve<T, R>(
    asset: &Asset<T>,
    registry: &KycRegistry<R>,
    identity: IdentityKey,
    time: Time,
): KycApproval<T> {
    let now_ms = authority::time_to_option(time);
    assert!(registry.records.contains(identity), EIdentityNotApproved);
    let record = registry.records.borrow(identity);
    assert!(kyc::approved_now(record, &now_ms), EIdentityNotApproved);
    kyc_proof::new(
        asset::id(asset),
        identity,
        kyc_proof::source_key<R>(object::id(registry)),
        kyc::expires_ms(record),
    )
}

public fun destroy_cap<R>(cap: KycRegistryCap<R>) {
    let KycRegistryCap { id, registry_id: _ } = cap;
    id.delete();
}

#[test_only]
public fun new_for_testing<R>(ctx: &mut TxContext): (KycRegistry<R>, KycRegistryCap<R>) {
    let registry = KycRegistry<R> {
        id: object::new(ctx),
        records: table::new(ctx),
    };
    let registry_id = object::id(&registry);
    let cap = KycRegistryCap { id: object::new(ctx), registry_id };
    (registry, cap)
}

#[test_only]
public fun destroy_empty_for_testing<R>(registry: KycRegistry<R>, cap: KycRegistryCap<R>) {
    assert_cap(&registry, &cap);
    let KycRegistry { id, records } = registry;
    records.destroy_empty();
    id.delete();
    destroy_cap(cap);
}

#[test_only]
public fun destroy_empty_registry_for_testing<R>(registry: KycRegistry<R>) {
    let KycRegistry { id, records } = registry;
    records.destroy_empty();
    id.delete();
}

fun assert_cap<R>(registry: &KycRegistry<R>, cap: &KycRegistryCap<R>) {
    assert!(object::id(registry) == cap.registry_id, ECapRegistryMismatch);
}

fun emit_kyc_updated<R>(
    registry_id: ID,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    event::emit(KycRegistryUpdatedEvent {
        registry_id,
        source_type: type_name::with_original_ids<R>(),
        identity,
        status,
        expires_ms,
        external_ref_hash,
    });
}
