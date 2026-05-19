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
    FreezeCap,
    MetadataCap,
    MintCap,
    PauseCap,
    PolicyCap,
    RegistrationCap,
};
use regulated_account::keys::{HolderKey, IdentityKey};
use regulated_account::kyc_proof::{KycApproval, KycSourceConfig};
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
    CloseMintCap<T>,
) {
    new_asset_with_kyc_sources(mode, vector[], ctx)
}

public fun new_asset_with_kyc_sources<T>(
    mode: u8,
    kyc_sources: vector<KycSourceConfig>,
    ctx: &mut TxContext,
): (
    Asset<T>,
    MintCap<T>,
    PolicyCap<T>,
    FreezeCap<T>,
    BurnCap<T>,
    ClawbackCap<T>,
    CloseMintCap<T>,
) {
    let asset = asset::new<T>(option::none(), mode, true, kyc_sources, ctx);
    let asset_id = asset::id(&asset);
    (
        asset,
        caps::new_mint(asset_id, ctx),
        caps::new_policy(asset_id, ctx),
        caps::new_freeze(asset_id, ctx),
        caps::new_burn(asset_id, ctx),
        caps::new_clawback(asset_id, ctx),
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
    let approvals = vector[];
    asset::assert_identity_not_frozen(asset, identity);
    asset::assert_identity_credit_allowed_with_approvals(asset, identity, &now_ms, &approvals);
    approvals.destroy_empty();
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

public fun new_account_with_approvals<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    allow_public_credits: bool,
    approvals: &vector<KycApproval<T>>,
    ctx: &mut TxContext,
): Account<T> {
    new_account_with_identity_and_approvals(
        asset,
        holder,
        regulated_account::keys::identity_from_holder(holder),
        allow_public_credits,
        approvals,
        ctx,
    )
}

public fun new_account_with_identity_and_approvals<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    allow_public_credits: bool,
    approvals: &vector<KycApproval<T>>,
    ctx: &mut TxContext,
): Account<T> {
    let now_ms = option::none();
    asset::assert_identity_not_frozen(asset, identity);
    asset::assert_identity_credit_allowed_with_approvals(asset, identity, &now_ms, approvals);
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
    let approvals = vector[];
    asset::assert_identity_not_frozen(asset, identity);
    asset::assert_identity_credit_allowed_with_approvals(asset, identity, &now_ms, &approvals);
    approvals.destroy_empty();
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
