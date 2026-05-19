#[test_only]
module regulated_account::test_helpers;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, Time};
use regulated_account::caps::{
    Self,
    BurnCap,
    ClawbackCap,
    CloseMintCap,
    FeeCap,
    FreezeCap,
    MetadataCap,
    MintCap,
    PauseCap,
    PolicyCap,
    RegistrationCap,
};
use regulated_account::keys::{HolderKey, IdentityKey};
use regulated_account::metadata::{Self, AssetMetadata, MetadataRegistry};
use regulated_account::receipt::Receipt;

public fun new_metadata_registry(ctx: &mut TxContext): MetadataRegistry {
    metadata::new_registry(ctx)
}

public fun remove_registered_metadata<T>(registry: &mut MetadataRegistry): ID {
    metadata::remove_registered_for_testing<T>(registry)
}

public fun destroy_metadata_registry(registry: MetadataRegistry) {
    metadata::destroy_for_testing(registry)
}

public fun new_asset<T>(
    mode: u8,
    ctx: &mut TxContext,
): (
    Asset<T>,
    MintCap<T>,
    PolicyCap<T>,
    FreezeCap<T>,
    BurnCap<T>,
    ClawbackCap<T>,
    FeeCap<T>,
    CloseMintCap<T>,
) {
    let asset = asset::new<T>(option::none(), mode, true, ctx);
    let asset_id = asset::id(&asset);
    (
        asset,
        caps::new_mint(asset_id, ctx),
        caps::new_policy(asset_id, ctx),
        caps::new_freeze(asset_id, ctx),
        caps::new_burn(asset_id, ctx),
        caps::new_clawback(asset_id, ctx),
        caps::new_fee(asset_id, ctx),
        caps::new_close_mint(asset_id, ctx),
    )
}

public fun new_metadata<T>(
    asset: &Asset<T>,
    ctx: &mut TxContext,
): (AssetMetadata<Receipt<T>>, MetadataCap<Receipt<T>>) {
    let metadata = metadata::new<T>(
        asset::id(asset),
        b"RT".to_string(),
        b"Regulated Account".to_string(),
        b"Regulated token test asset".to_string(),
        b"https://example.com/rt.png".to_string(),
        9,
        ctx,
    );
    let metadata_id = metadata::id(&metadata);
    (
        metadata,
        caps::new_metadata(metadata_id, ctx),
    )
}

public fun new_pause_cap<T>(asset: &Asset<T>, ctx: &mut TxContext): PauseCap<T> {
    caps::new_pause(asset::id(asset), ctx)
}

public fun set_display_scale<T>(asset: &mut Asset<T>, numerator: u64, denominator: u64) {
    asset::set_display_scale_for_testing(asset, numerator, denominator);
}

public fun new_registration_cap<T>(
    asset: &Asset<T>,
    ctx: &mut TxContext,
): RegistrationCap<T> {
    caps::new_registration(asset::id(asset), ctx)
}

public fun new_account<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    allow_public_credits: bool,
    ctx: &mut TxContext,
): Account<T> {
    new_account_with_identity(
        asset,
        holder,
        regulated_account::keys::identity_from_holder(holder),
        allow_public_credits,
        ctx,
    )
}

public fun new_account_with_identity<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    allow_public_credits: bool,
    ctx: &mut TxContext,
): Account<T> {
    let now_ms = option::none();
    asset::assert_identity_allowed(asset, identity, &now_ms);
    account::new(
        asset::id(asset),
        holder,
        identity,
        asset::default_account_frozen(asset),
        false,
        false,
        allow_public_credits,
        ctx,
    )
}

public fun new_account_at_time<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    allow_public_credits: bool,
    time: Time,
    ctx: &mut TxContext,
): Account<T> {
    new_account_with_identity_at_time(
        asset,
        holder,
        regulated_account::keys::identity_from_holder(holder),
        allow_public_credits,
        time,
        ctx,
    )
}

public fun new_account_with_identity_at_time<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    allow_public_credits: bool,
    time: Time,
    ctx: &mut TxContext,
): Account<T> {
    let now_ms = authority::time_to_option(time);
    asset::assert_identity_allowed(asset, identity, &now_ms);
    account::new(
        asset::id(asset),
        holder,
        identity,
        asset::default_account_frozen(asset),
        false,
        false,
        allow_public_credits,
        ctx,
    )
}
