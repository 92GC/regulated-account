module regulated_account::regulated_account;

use std::string::String;
use std::type_name;
use regulated_account::account;
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
use regulated_account::events;
use regulated_account::keys::{Self, HolderKey, IdentityKey};
use regulated_account::kyc_proof::{Self, KycApproval, KycSourceConfig};
use regulated_account::metadata;
use regulated_account::receipt::{Self, Receipt};
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
    kyc_sources: vector<KycSourceConfig>,
    ctx: &mut TxContext,
): (
    MintCap<T>,
    FreezeCap<T>,
    BurnCap<T>,
    ClawbackCap<T>,
    PolicyCap<T>,
    RegistrationCap<T>,
    MetadataCap<Receipt<T>>,
    PauseCap<T>,
    CloseMintCap<T>,
) {
    assert!(types::is_one_time_witness(&witness), EBadWitness);
    validation::assert_metadata_fields(&symbol, &name, &description, &icon_url);

    let asset = asset::new<T>(max_supply, mode, mode_mutable, kyc_sources, ctx);
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

    let mint_cap = caps::new_mint<T>(asset_id, ctx);
    let freeze_cap = caps::new_freeze<T>(asset_id, ctx);
    let burn_cap = caps::new_burn<T>(asset_id, ctx);
    let clawback_cap = caps::new_clawback<T>(asset_id, ctx);
    let policy_cap = caps::new_policy<T>(asset_id, ctx);
    let registration_cap = caps::new_registration<T>(asset_id, ctx);
    let metadata_cap = caps::new_metadata<Receipt<T>>(metadata_id, ctx);
    let pause_cap = caps::new_pause<T>(asset_id, ctx);
    let close_mint_cap = caps::new_close_mint<T>(asset_id, ctx);

    events::emit_asset_created(
        asset_id,
        metadata_id,
        type_name::with_original_ids<Receipt<T>>(),
        ctx.sender(),
        mode,
        max_supply,
    );
    metadata::share(metadata);
    asset::share(asset);

    (
        mint_cap,
        freeze_cap,
        burn_cap,
        clawback_cap,
        policy_cap,
        registration_cap,
        metadata_cap,
        pause_cap,
        close_mint_cap,
    )
}

public fun create_account<T>(
    asset: &Asset<T>,
    time: Time,
    approvals: vector<KycApproval<T>>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
) {
    asset::assert_not_paused(asset);
    account::assert_own_address_account(holder, identity, ctx);
    create_account_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        false,
        memo_required,
        allow_public_credits,
        authority::time_to_option(time),
        &approvals,
        ctx,
    );
    kyc_proof::destroy_all(approvals);
}

public fun admin_create_account<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    time: Time,
    approvals: vector<KycApproval<T>>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_holder: bool,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
) {
    caps::assert_registration(asset::id(asset), cap);
    asset::assert_not_paused(asset);
    create_account_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        immutable_holder,
        memo_required,
        allow_public_credits,
        authority::time_to_option(time),
        &approvals,
        ctx,
    );
    kyc_proof::destroy_all(approvals);
}

fun create_account_internal<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_holder: bool,
    memo_required: bool,
    allow_public_credits: bool,
    now_ms: Option<u64>,
    approvals: &vector<KycApproval<T>>,
    ctx: &mut TxContext,
) {
    keys::assert_valid_holder(holder);
    keys::assert_valid_identity(identity);
    asset::assert_identity_not_frozen(asset, identity);
    asset::assert_identity_credit_allowed_with_approvals(asset, identity, &now_ms, approvals);
    let new_account = account::new<T>(
        asset::id(asset),
        holder,
        identity,
        asset::default_account_frozen(asset),
        immutable_holder,
        memo_required,
        allow_public_credits,
        ctx,
    );
    let account_id = account::id(&new_account);
    let receipt_id = if (receipt_recipient.is_some()) {
        let receipt = receipt::new<T>(asset::id(asset), account_id, ctx);
        let id = object::id(&receipt);
        transfer::public_transfer(receipt, *receipt_recipient.borrow());
        option::some(id)
    } else {
        option::none()
    };

    events::emit_account_created(asset::id(asset), account_id, holder, identity, receipt_id);
    account::share(new_account);
}
