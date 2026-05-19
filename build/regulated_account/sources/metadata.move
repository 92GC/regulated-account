module regulated_account::metadata;

use std::string::String;
use std::type_name;
use regulated_account::caps::{Self, MetadataCap};
use regulated_account::events;
use regulated_account::receipt::Receipt;
use regulated_account::validation;
use sui::table::{Self, Table};

const ECapAssetMismatch: u64 = 4;
const EMetadataAlreadyRegistered: u64 = 29;
const EMetadataNotRegistered: u64 = 30;

public struct MetadataRegistry has key {
    id: UID,
    metadata_by_receipt_type: Table<type_name::TypeName, ID>,
}

public struct AssetMetadata<phantom ReceiptType> has key {
    id: UID,
    asset_id: ID,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    decimals: u8,
}

public(package) fun new_registry(ctx: &mut TxContext): MetadataRegistry {
    MetadataRegistry {
        id: object::new(ctx),
        metadata_by_receipt_type: table::new(ctx),
    }
}

public(package) fun share_registry(registry: MetadataRegistry) {
    transfer::share_object(registry);
}

fun init(ctx: &mut TxContext) {
    share_registry(new_registry(ctx));
}

public(package) fun new<T>(
    asset_id: ID,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    decimals: u8,
    ctx: &mut TxContext,
): AssetMetadata<Receipt<T>> {
    validation::assert_metadata_fields(&symbol, &name, &description, &icon_url);
    AssetMetadata {
        id: object::new(ctx),
        asset_id,
        symbol,
        name,
        description,
        icon_url,
        decimals,
    }
}

public(package) fun share<T>(metadata: AssetMetadata<Receipt<T>>) {
    transfer::share_object(metadata);
}

public fun registry_id(registry: &MetadataRegistry): ID { object::id(registry) }
public fun id<T>(metadata: &AssetMetadata<Receipt<T>>): ID { object::id(metadata) }
public fun asset_id<T>(metadata: &AssetMetadata<Receipt<T>>): ID { metadata.asset_id }
public fun receipt_type<T>(): type_name::TypeName { type_name::with_original_ids<Receipt<T>>() }
public fun symbol<T>(metadata: &AssetMetadata<Receipt<T>>): String { metadata.symbol }
public fun name<T>(metadata: &AssetMetadata<Receipt<T>>): String { metadata.name }
public fun description<T>(metadata: &AssetMetadata<Receipt<T>>): String { metadata.description }
public fun icon_url<T>(metadata: &AssetMetadata<Receipt<T>>): String { metadata.icon_url }
public fun decimals<T>(metadata: &AssetMetadata<Receipt<T>>): u8 { metadata.decimals }

public fun registered<T>(registry: &MetadataRegistry): bool {
    registry.metadata_by_receipt_type.contains(receipt_type<T>())
}

public fun registered_id<T>(registry: &MetadataRegistry): Option<ID> {
    let receipt_type = receipt_type<T>();
    if (registry.metadata_by_receipt_type.contains(receipt_type)) {
        option::some(*registry.metadata_by_receipt_type.borrow(receipt_type))
    } else {
        option::none()
    }
}

public fun assert_registered<T>(
    registry: &MetadataRegistry,
    metadata: &AssetMetadata<Receipt<T>>,
) {
    let registered_id = registered_id<T>(registry);
    assert!(
        registered_id.is_some() && *registered_id.borrow() == object::id(metadata),
        EMetadataNotRegistered,
    );
}

public fun register<T>(
    registry: &mut MetadataRegistry,
    metadata: &AssetMetadata<Receipt<T>>,
) {
    let receipt_type = receipt_type<T>();
    assert!(
        !registry.metadata_by_receipt_type.contains(receipt_type),
        EMetadataAlreadyRegistered,
    );
    let metadata_id = object::id(metadata);
    registry.metadata_by_receipt_type.add(receipt_type, metadata_id);
    events::emit_metadata_registered(receipt_type, metadata_id, metadata.asset_id);
}

public fun set<T>(
    metadata: &mut AssetMetadata<Receipt<T>>,
    cap: &MetadataCap<Receipt<T>>,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
) {
    assert!(caps::metadata_id(cap) == object::id(metadata), ECapAssetMismatch);
    validation::assert_metadata_fields(&symbol, &name, &description, &icon_url);
    metadata.symbol = symbol;
    metadata.name = name;
    metadata.description = description;
    metadata.icon_url = icon_url;
    events::emit_metadata_updated(metadata.asset_id, symbol, name, description, icon_url);
}

#[test_only]
public fun remove_registered_for_testing<T>(registry: &mut MetadataRegistry): ID {
    let receipt_type = receipt_type<T>();
    assert!(registry.metadata_by_receipt_type.contains(receipt_type), EMetadataNotRegistered);
    registry.metadata_by_receipt_type.remove(receipt_type)
}

#[test_only]
public fun destroy_for_testing(registry: MetadataRegistry) {
    let MetadataRegistry { id, metadata_by_receipt_type } = registry;
    metadata_by_receipt_type.destroy_empty();
    id.delete();
}
