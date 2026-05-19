module regulated_account::regulated_account;

use std::string::String;
use std::type_name;
use regulated_account::account;
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::Time;
use regulated_account::caps::{Self, RegistrationCap};
use regulated_account::events;
use regulated_account::keys::{HolderKey, IdentityKey};
use regulated_account::metadata;
use regulated_account::receipt::Receipt;
use regulated_account::validation;
use sui::types;

const EBadWitness: u64 = 1;

public fun create_asset<T: drop>(
    witness: T,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    decimals: u8,
    max_supply: Option<u64>,
    mode: u8,
    mode_mutable: bool,
    admin: address,
    ctx: &mut TxContext,
) {
    assert!(types::is_one_time_witness(&witness), EBadWitness);
    validation::assert_metadata_fields(&symbol, &name, &description, &icon_url);

    let asset = asset::new<T>(max_supply, mode, mode_mutable, ctx);
    let asset_id = asset::id(&asset);
    let metadata = metadata::new<T>(
        asset_id,
        symbol,
        name,
        description,
        icon_url,
        decimals,
        ctx,
    );
    let metadata_id = metadata::id(&metadata);

    transfer::public_transfer(caps::new_mint<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_freeze<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_burn<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_clawback<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_policy<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_registration<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_fee<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_close_mint<T>(asset_id, ctx), admin);
    transfer::public_transfer(caps::new_metadata<Receipt<T>>(metadata_id, ctx), admin);
    transfer::public_transfer(caps::new_pause<T>(asset_id, ctx), admin);

    events::emit_asset_created(
        asset_id,
        metadata_id,
        type_name::with_original_ids<Receipt<T>>(),
        admin,
        mode,
        max_supply,
    );
    metadata::share(metadata);
    asset::share(asset);
}

public fun create_account<T>(
    asset: &Asset<T>,
    time: Time,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
) {
    account::create(
        asset,
        time,
        holder,
        identity,
        receipt_recipient,
        memo_required,
        allow_public_credits,
        ctx,
    )
}

public fun admin_create_account<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    time: Time,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
) {
    account::admin_create(
        asset,
        cap,
        time,
        holder,
        identity,
        receipt_recipient,
        immutable_owner,
        memo_required,
        allow_public_credits,
        ctx,
    )
}
