module regulated_account::regulated_account;

use std::string::String;
use std::type_name;
use sui::clock::{Self, Clock};
use sui::event;
use sui::group_ops::{Self, Element};
use sui::rangeproofs;
use sui::ristretto255;
use sui::table::{Self, Table};
use sui::types;
use sui::vec_set::{Self, VecSet};

// === Constants ===

const HOLDER_ADDRESS: u8 = 0;
const HOLDER_OBJECT: u8 = 1;
const HOLDER_PACKAGE: u8 = 2;

const IDENTITY_ADDRESS: u8 = 0;
const IDENTITY_OBJECT: u8 = 1;
const IDENTITY_EXTERNAL: u8 = 2;

const MODE_ALLOWLIST: u8 = 0;
const MODE_DENYLIST: u8 = 1;
const MODE_OPEN: u8 = 2;

const KYC_UNKNOWN: u8 = 0;
const KYC_APPROVED: u8 = 1;
const KYC_DENIED: u8 = 2;
const KYC_PENDING: u8 = 3;
const KYC_EXPIRED: u8 = 4;
const KYC_EXEMPT: u8 = 5;

const AUTH_ACTIVE: u8 = 1;
const AUTH_PERMANENT: u8 = 2;

const MAX_BPS: u64 = 10_000;
const MAX_PENDING_CONFIDENTIAL_NOTES: u64 = 64;
const MAX_RESTRICTED_LOTS: u64 = 128;
const MAX_MEMO_BYTES: u64 = 256;
const MAX_EXTERNAL_REF_HASH_BYTES: u64 = 64;
const MAX_VIEWER_POLICY_HASH_BYTES: u64 = 128;
const MAX_ENCRYPTED_NOTE_BYTES: u64 = 1_024;
const MAX_VIEWER_NOTES: u64 = 16;
const MAX_ENCRYPTED_OPENINGS: u64 = 16;
const RANGE_BITS_U64: u8 = 64;
const BULLETPROOFS_VERSION: u8 = 0;
const RISTRETTO_POINT_BYTES: u64 = 32;

// === Errors ===

const EBadWitness: u64 = 1;
const EInvalidMode: u64 = 2;
const EInvalidHolderKind: u64 = 3;
const EAssetMismatch: u64 = 4;
const ECapAssetMismatch: u64 = 5;
const ENotAuthorized: u64 = 6;
const EAccountFrozen: u64 = 7;
const EHolderNotAllowed: u64 = 8;
const EInsufficientBalance: u64 = 9;
const EInvalidFee: u64 = 10;
const EMemoRequired: u64 = 11;
const EPolicyImmutable: u64 = 12;
const EMintClosed: u64 = 13;
const EPrivacyDisabled: u64 = 14;
const EConfidentialCreditDisabled: u64 = 15;
const EPublicCreditDisabled: u64 = 16;
const EInvalidCommitment: u64 = 17;
const EInvalidRangeProof: u64 = 18;
const EConfidentialFeesUnsupported: u64 = 19;
const EImmutableOwner: u64 = 20;
const EFeeReceiverRequired: u64 = 21;
const EConfidentialAccountDisabled: u64 = 22;
const EUseTransferWithFee: u64 = 23;
const EAuthorizationPermanent: u64 = 24;
const EAmountOverflow: u64 = 25;
const EConfidentialPendingNotEmpty: u64 = 26;
const EMaxPendingConfidentialNotes: u64 = 27;
const EInvalidDisplayScale: u64 = 28;
const EPaused: u64 = 29;
const ENonTransferable: u64 = 30;
const ETransferRulesRequired: u64 = 31;
const ETransferRuleMissing: u64 = 32;
const ETransferRequestMismatch: u64 = 33;
const EMaxSupplyExceeded: u64 = 34;
const EShareholderCapExceeded: u64 = 36;
const ELockedBalanceExceeded: u64 = 38;
const ERestrictedLotLimit: u64 = 39;
const EConfidentialShareholderCapsUnsupported: u64 = 40;
const EInvalidKycStatus: u64 = 41;
const EInvalidVectorSize: u64 = 42;
const EConfidentialMaxSupplyUnsupported: u64 = 43;

// === Core Types ===

public struct HolderKey has copy, drop, store {
    kind: u8,
    addr: address,
}

public struct IdentityKey has copy, drop, store {
    kind: u8,
    addr: address,
}

public struct KycRecord has copy, drop, store {
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
}

public struct RestrictedLot has copy, drop, store {
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
}

public struct FeeConfig has copy, drop, store {
    bps: u64,
    fixed: u64,
    receiver: Option<ID>,
}

public struct PrivacyConfig has copy, drop, store {
    enabled: bool,
    viewer_policy_hash: vector<u8>,
    confidential_supply_commitment: Element<ristretto255::G>,
}

public struct ConfidentialBalance has store {
    enabled: bool,
    available: Element<ristretto255::G>,
    pending: Element<ristretto255::G>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
    encrypted_pending_notes: Table<u64, PendingEncryptedNote>,
    pending_note_count: u64,
    max_pending_notes: u64,
}

public struct PendingEncryptedNote has copy, drop, store {
    // Availability payloads are not consensus-critical: commitment arithmetic
    // preserves value, but this module does not prove the ciphertext opens to
    // the same blinding/value. Issuers that need that property should require
    // an external transfer rule with an equality proof.
    recipient_note: vector<u8>,
    viewer_notes: vector<vector<u8>>,
}

public struct Asset<phantom T> has key {
    id: UID,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
    decimals: u8,
    supply: u64,
    max_supply: Option<u64>,
    total_shareholders: u64,
    max_shareholders: Option<u64>,
    display_scale_numerator: u64,
    display_scale_denominator: u64,
    metadata_pointer: Option<ID>,
    group_pointer: Option<ID>,
    group_member_pointer: Option<ID>,
    mode: u8,
    mode_mutable: bool,
    mint_closed: bool,
    paused: bool,
    default_account_frozen: bool,
    non_transferable: bool,
    fee: FeeConfig,
    privacy: PrivacyConfig,
    kyc: Table<IdentityKey, KycRecord>,
    shareholder_accounts: Table<IdentityKey, u64>,
    transfer_rules: VecSet<type_name::TypeName>,
    authorized_witnesses: Table<type_name::TypeName, u8>,
    authorized_packages: Table<address, u8>,
    authorized_object_holders: Table<ID, u8>,
}

public struct Account<phantom T> has key {
    id: UID,
    asset_id: ID,
    holder: HolderKey,
    identity: IdentityKey,
    balance: u64,
    locked_balance: u64,
    restricted_lots: vector<RestrictedLot>,
    frozen: bool,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    confidential: ConfidentialBalance,
}

/// Wallet-discovery receipt. This is not an authorization primitive.
public struct Receipt<phantom T> has key, store {
    id: UID,
    asset_id: ID,
    account_id: ID,
}

/// Hot-potato transfer request for optional external rule composition.
public struct TransferRequest<phantom T> {
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    fee_account: Option<ID>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
    approvals: VecSet<type_name::TypeName>,
}

/// Hot-potato confidential transfer request for external rule composition.
public struct ConfidentialTransferRequest<phantom T> {
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    now_ms: Option<u64>,
    approvals: VecSet<type_name::TypeName>,
}

// === Caps ===

public struct MintCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct FreezeCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct BurnCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct ClawbackCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct PolicyCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct RegistrationCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct FeeCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct CloseMintCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct MetadataCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct PauseCap<phantom T> has key, store { id: UID, asset_id: ID }

// === Events ===

public struct AssetCreated has copy, drop {
    asset_id: ID,
    issuer: address,
    mode: u8,
    max_supply: Option<u64>,
    privacy_enabled: bool,
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
    gross_amount: u64,
    fee_amount: u64,
    net_amount: u64,
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
}

public struct ClawbackEvent has copy, drop {
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount: u64,
}

public struct FreezeEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    frozen: bool,
}

public struct KycUpdatedEvent has copy, drop {
    asset_id: ID,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
}

public struct FeeConfigUpdatedEvent has copy, drop {
    asset_id: ID,
    bps: u64,
    fixed: u64,
    receiver: Option<ID>,
}

public struct MetadataUpdatedEvent has copy, drop {
    asset_id: ID,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
}

public struct DisplayScaleUpdatedEvent has copy, drop {
    asset_id: ID,
    numerator: u64,
    denominator: u64,
}

public struct MaxSupplyUpdatedEvent has copy, drop {
    asset_id: ID,
    max_supply: Option<u64>,
}

public struct ShareholderCapsUpdatedEvent has copy, drop {
    asset_id: ID,
    max_shareholders: Option<u64>,
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
}

public struct MetadataPointerUpdatedEvent has copy, drop {
    asset_id: ID,
    metadata_pointer: Option<ID>,
}

public struct GroupPointersUpdatedEvent has copy, drop {
    asset_id: ID,
    group_pointer: Option<ID>,
    group_member_pointer: Option<ID>,
}

public struct PauseEvent has copy, drop {
    asset_id: ID,
    paused: bool,
}

public struct DefaultAccountStateUpdatedEvent has copy, drop {
    asset_id: ID,
    frozen: bool,
}

public struct NonTransferableEvent has copy, drop {
    asset_id: ID,
}

public struct WitnessAuthorizationUpdatedEvent has copy, drop {
    asset_id: ID,
    witness: type_name::TypeName,
    status: u8,
}

public struct PackageAuthorizationUpdatedEvent has copy, drop {
    asset_id: ID,
    package_addr: address,
    status: u8,
}

public struct ObjectAuthorityUpdatedEvent has copy, drop {
    asset_id: ID,
    object_id: ID,
    status: u8,
}

public struct TransferRuleUpdatedEvent has copy, drop {
    asset_id: ID,
    rule: type_name::TypeName,
    enabled: bool,
}

public struct ViewerPolicyUpdatedEvent has copy, drop {
    asset_id: ID,
    viewer_policy_hash: vector<u8>,
}

public struct ConfidentialTransferEvent has copy, drop {
    asset_id: ID,
    from_account: ID,
    to_account: ID,
    amount_commitment: Element<ristretto255::G>,
    memo: vector<u8>,
}

public struct ConfidentialMintEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    amount_commitment: Element<ristretto255::G>,
}

public struct ConfidentialBurnEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    amount_commitment: Element<ristretto255::G>,
}

public struct AccountFlagsUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
}

public struct ConfidentialPendingLimitUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    max_pending_notes: u64,
}

public struct LockedBalanceUpdatedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
    locked_balance: u64,
}

public struct OwnerLockedEvent has copy, drop {
    asset_id: ID,
    account_id: ID,
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
}

// === Constructors ===

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
    privacy_enabled: bool,
    viewer_policy_hash: vector<u8>,
    admin: address,
    ctx: &mut TxContext,
) {
    assert!(types::is_one_time_witness(&witness), EBadWitness);
    assert_valid_mode(mode);
    assert!(!privacy_enabled || max_supply.is_none(), EConfidentialMaxSupplyUnsupported);
    assert_vector_size(&viewer_policy_hash, MAX_VIEWER_POLICY_HASH_BYTES);

    let asset_uid = object::new(ctx);
    let asset_id = object::uid_to_inner(&asset_uid);
    let asset = Asset<T> {
        id: asset_uid,
        symbol,
        name,
        description,
        icon_url,
        decimals,
        supply: 0,
        max_supply,
        total_shareholders: 0,
        max_shareholders: option::none(),
        display_scale_numerator: 1,
        display_scale_denominator: 1,
        metadata_pointer: option::none(),
        group_pointer: option::none(),
        group_member_pointer: option::none(),
        mode,
        mode_mutable,
        mint_closed: false,
        paused: false,
        default_account_frozen: false,
        non_transferable: false,
        fee: FeeConfig { bps: 0, fixed: 0, receiver: option::none() },
        privacy: PrivacyConfig {
            enabled: privacy_enabled,
            viewer_policy_hash,
            confidential_supply_commitment: ristretto255::g_identity(),
        },
        kyc: table::new(ctx),
        shareholder_accounts: table::new(ctx),
        transfer_rules: vec_set::empty(),
        authorized_witnesses: table::new(ctx),
        authorized_packages: table::new(ctx),
        authorized_object_holders: table::new(ctx),
    };

    transfer::public_transfer(MintCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(FreezeCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(BurnCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(ClawbackCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(PolicyCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(RegistrationCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(FeeCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(CloseMintCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(MetadataCap<T> { id: object::new(ctx), asset_id }, admin);
    transfer::public_transfer(PauseCap<T> { id: object::new(ctx), asset_id }, admin);

    event::emit(AssetCreated { asset_id, issuer: admin, mode, max_supply, privacy_enabled });
    transfer::share_object(asset);
}

public fun create_account<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    ctx: &mut TxContext,
) {
    assert_own_address_account(holder, identity, ctx);
    create_account_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        immutable_owner,
        memo_required,
        allow_public_credits,
        allow_confidential_credits,
        owner_encrypted_opening,
        encrypted_openings_for_viewers,
        option::none(),
        ctx,
    )
}

public fun create_account_with_clock<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_own_address_account(holder, identity, ctx);
    create_account_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        immutable_owner,
        memo_required,
        allow_public_credits,
        allow_confidential_credits,
        owner_encrypted_opening,
        encrypted_openings_for_viewers,
        option::some(clock::timestamp_ms(clock)),
        ctx,
    )
}

public fun admin_create_account<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    ctx: &mut TxContext,
) {
    assert_cap(asset, cap.asset_id);
    create_account_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        immutable_owner,
        memo_required,
        allow_public_credits,
        allow_confidential_credits,
        owner_encrypted_opening,
        encrypted_openings_for_viewers,
        option::none(),
        ctx,
    )
}

public fun admin_create_account_with_clock<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    clock: &Clock,
    ctx: &mut TxContext,
) {
    assert_cap(asset, cap.asset_id);
    create_account_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        immutable_owner,
        memo_required,
        allow_public_credits,
        allow_confidential_credits,
        owner_encrypted_opening,
        encrypted_openings_for_viewers,
        option::some(clock::timestamp_ms(clock)),
        ctx,
    )
}

public fun destroy_receipt<T>(receipt: Receipt<T>) {
    let Receipt { id, asset_id: _, account_id: _ } = receipt;
    id.delete();
}

fun create_account_internal<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_owner: bool,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    now_ms: Option<u64>,
    ctx: &mut TxContext,
) {
    assert_valid_holder(holder);
    assert_valid_identity(identity);
    assert_opening_bytes(&owner_encrypted_opening);
    assert_opening_bytes_vector(&encrypted_openings_for_viewers);
    assert_identity_allowed(asset, identity, &now_ms);

    let account_uid = object::new(ctx);
    let account_id = object::uid_to_inner(&account_uid);
    let asset_id = object::id(asset);
    let receipt_id = if (receipt_recipient.is_some()) {
        let receipt = Receipt<T> {
            id: object::new(ctx),
            asset_id,
            account_id,
        };
        let id = object::id(&receipt);
        transfer::public_transfer(receipt, *receipt_recipient.borrow());
        option::some(id)
    } else {
        option::none()
    };

    let account = Account<T> {
        id: account_uid,
        asset_id,
        holder,
        identity,
        balance: 0,
        locked_balance: 0,
        restricted_lots: vector[],
        frozen: asset.default_account_frozen,
        immutable_owner,
        memo_required,
        allow_public_credits,
        allow_confidential_credits,
        confidential: ConfidentialBalance {
            enabled: asset.privacy.enabled,
            available: ristretto255::g_identity(),
            pending: ristretto255::g_identity(),
            encrypted_available_for_owner: owner_encrypted_opening,
            encrypted_available_for_viewers: encrypted_openings_for_viewers,
            encrypted_pending_notes: table::new(ctx),
            pending_note_count: 0,
            max_pending_notes: MAX_PENDING_CONFIDENTIAL_NOTES,
        },
    };

    event::emit(AccountCreated { asset_id, account_id, holder, identity, receipt_id });
    transfer::share_object(account);
}

// === Public Balance Operations ===

public fun mint<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
) {
    mint_internal(asset, cap, to, amount, option::none())
}

public fun mint_with_clock<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    clock: &Clock,
) {
    mint_internal(asset, cap, to, amount, option::some(clock::timestamp_ms(clock)))
}

public fun mint_restricted<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
) {
    mint_restricted_internal(asset, cap, to, amount, unlock_ms, external_ref_hash, option::none())
}

public fun mint_restricted_with_clock<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
    clock: &Clock,
) {
    mint_restricted_internal(
        asset,
        cap,
        to,
        amount,
        unlock_ms,
        external_ref_hash,
        option::some(clock::timestamp_ms(clock)),
    )
}

fun mint_internal<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    now_ms: Option<u64>,
) {
    // Pause is a movement halt. Issuers may still mint during a paused
    // corporate action or incident workflow.
    assert_cap(asset, cap.asset_id);
    assert!(!asset.mint_closed, EMintClosed);
    assert_account(asset, to);
    assert_not_frozen(to);
    assert_public_credit_allowed(asset, to, &now_ms);

    let new_supply = checked_add(asset.supply, amount);
    assert_max_supply(asset.max_supply, new_supply);
    let _display_supply = scaled_u64(
        new_supply,
        asset.display_scale_numerator,
        asset.display_scale_denominator,
    );

    credit_account(asset, to, amount);
    asset.supply = new_supply;

    event::emit(MintEvent {
        asset_id: object::id(asset),
        account_id: object::id(to),
        amount,
    });
}

fun mint_restricted_internal<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_restricted_lot_capacity(to);
    assert_external_ref_hash(&external_ref_hash);
    mint_internal(asset, cap, to, amount, now_ms);
    to.restricted_lots.push_back(RestrictedLot {
        amount,
        unlock_ms,
        external_ref_hash,
    });

    event::emit(RestrictedMintEvent {
        asset_id: object::id(asset),
        account_id: object::id(to),
        amount,
        unlock_ms,
        external_ref_hash,
    });
}

public fun transfer<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    ctx: &TxContext,
) {
    assert_owner_authorized(from, ctx);
    transfer_internal(asset, from, to, amount, memo, option::none());
}

public fun transfer_with_clock<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert_owner_authorized(from, ctx);
    transfer_internal(asset, from, to, amount, memo, option::some(clock::timestamp_ms(clock)));
}

public fun transfer_with_fee_account<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    ctx: &TxContext,
) {
    assert_owner_authorized(from, ctx);
    transfer_with_fee_internal(asset, from, to, fee_account, amount, memo, option::none());
}

public fun transfer_with_fee_account_with_clock<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert_owner_authorized(from, ctx);
    transfer_with_fee_internal(
        asset,
        from,
        to,
        fee_account,
        amount,
        memo,
        option::some(clock::timestamp_ms(clock)),
    );
}

public fun transfer_with_fee_account_with_object_authority<T, Authority: key>(
    asset: &mut Asset<T>,
    authority: &Authority,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    assert_object_authorized(asset, authority, from);
    transfer_with_fee_internal(asset, from, to, fee_account, amount, memo, option::none());
}

public fun transfer_with_fee_account_with_object_authority_and_clock<T, Authority: key>(
    asset: &mut Asset<T>,
    authority: &Authority,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
) {
    assert_object_authorized(asset, authority, from);
    transfer_with_fee_internal(
        asset,
        from,
        to,
        fee_account,
        amount,
        memo,
        option::some(clock::timestamp_ms(clock)),
    );
}

public fun transfer_with_fee_account_with_package_witness<T, W: drop>(
    asset: &mut Asset<T>,
    witness: W,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    transfer_with_fee_internal(asset, from, to, fee_account, amount, memo, option::none());
}

public fun transfer_with_fee_account_with_package_witness_and_clock<T, W: drop>(
    asset: &mut Asset<T>,
    witness: W,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    transfer_with_fee_internal(
        asset,
        from,
        to,
        fee_account,
        amount,
        memo,
        option::some(clock::timestamp_ms(clock)),
    );
}

public fun transfer_with_object_authority<T, Authority: key>(
    asset: &mut Asset<T>,
    authority: &Authority,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    assert_object_authorized(asset, authority, from);
    transfer_internal(asset, from, to, amount, memo, option::none());
}

public fun transfer_with_object_authority_and_clock<T, Authority: key>(
    asset: &mut Asset<T>,
    authority: &Authority,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
) {
    assert_object_authorized(asset, authority, from);
    transfer_internal(asset, from, to, amount, memo, option::some(clock::timestamp_ms(clock)));
}

public fun transfer_with_package_witness<T, W: drop>(
    asset: &mut Asset<T>,
    witness: W,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    transfer_internal(asset, from, to, amount, memo, option::none());
}

public fun transfer_with_package_witness_and_clock<T, W: drop>(
    asset: &mut Asset<T>,
    witness: W,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    transfer_internal(asset, from, to, amount, memo, option::some(clock::timestamp_ms(clock)));
}

public fun request_transfer<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    amount: u64,
    memo: vector<u8>,
    ctx: &TxContext,
): TransferRequest<T> {
    assert_owner_authorized(from, ctx);
    new_transfer_request(asset, from, to, option::none(), amount, memo, option::none())
}

public fun request_transfer_with_clock<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
): TransferRequest<T> {
    assert_owner_authorized(from, ctx);
    new_transfer_request(
        asset,
        from,
        to,
        option::none(),
        amount,
        memo,
        option::some(clock::timestamp_ms(clock)),
    )
}

public fun request_transfer_with_fee_account<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    fee_account: &Account<T>,
    amount: u64,
    memo: vector<u8>,
    ctx: &TxContext,
): TransferRequest<T> {
    assert_owner_authorized(from, ctx);
    assert_account(asset, fee_account);
    new_transfer_request(
        asset,
        from,
        to,
        option::some(object::id(fee_account)),
        amount,
        memo,
        option::none(),
    )
}

public fun request_transfer_with_fee_account_with_clock<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    fee_account: &Account<T>,
    amount: u64,
    memo: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
): TransferRequest<T> {
    assert_owner_authorized(from, ctx);
    assert_account(asset, fee_account);
    new_transfer_request(
        asset,
        from,
        to,
        option::some(object::id(fee_account)),
        amount,
        memo,
        option::some(clock::timestamp_ms(clock)),
    )
}

public fun request_transfer_with_object_authority<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    from: &Account<T>,
    to: &Account<T>,
    amount: u64,
    memo: vector<u8>,
): TransferRequest<T> {
    assert_object_authorized(asset, authority, from);
    new_transfer_request(asset, from, to, option::none(), amount, memo, option::none())
}

public fun request_transfer_with_package_witness<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    from: &Account<T>,
    to: &Account<T>,
    amount: u64,
    memo: vector<u8>,
): TransferRequest<T> {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    new_transfer_request(asset, from, to, option::none(), amount, memo, option::none())
}

public fun add_transfer_rule_approval<T, Rule: drop>(
    _rule: Rule,
    request: &mut TransferRequest<T>,
) {
    request.approvals.insert(type_name::with_original_ids<Rule>());
}

public fun confirm_transfer<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    request: TransferRequest<T>,
) {
    let (amount, memo, now_ms) = confirm_transfer_request(
        asset,
        object::id(from),
        object::id(to),
        option::none(),
        request,
    );
    transfer_internal_after_rules(asset, from, to, amount, memo, now_ms);
}

public fun confirm_transfer_with_fee_account<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    request: TransferRequest<T>,
) {
    let (amount, memo, now_ms) = confirm_transfer_request(
        asset,
        object::id(from),
        object::id(to),
        option::some(object::id(fee_account)),
        request,
    );
    transfer_with_fee_internal_after_rules(asset, from, to, fee_account, amount, memo, now_ms);
}

public fun burn<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
    ctx: &TxContext,
) {
    assert_owner_authorized(account, ctx);
    burn_internal(asset, account, amount, false, option::none());
}

public fun burn_with_clock<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert_owner_authorized(account, ctx);
    burn_internal(asset, account, amount, false, option::some(clock::timestamp_ms(clock)));
}

public fun burn_with_object_authority<T, Authority: key>(
    asset: &mut Asset<T>,
    authority: &Authority,
    account: &mut Account<T>,
    amount: u64,
) {
    assert_object_authorized(asset, authority, account);
    burn_internal(asset, account, amount, false, option::none());
}

public fun burn_with_object_authority_and_clock<T, Authority: key>(
    asset: &mut Asset<T>,
    authority: &Authority,
    account: &mut Account<T>,
    amount: u64,
    clock: &Clock,
) {
    assert_object_authorized(asset, authority, account);
    burn_internal(asset, account, amount, false, option::some(clock::timestamp_ms(clock)));
}

public fun burn_with_package_witness<T, W: drop>(
    asset: &mut Asset<T>,
    witness: W,
    account: &mut Account<T>,
    amount: u64,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, account);
    burn_internal(asset, account, amount, false, option::none());
}

public fun burn_with_package_witness_and_clock<T, W: drop>(
    asset: &mut Asset<T>,
    witness: W,
    account: &mut Account<T>,
    amount: u64,
    clock: &Clock,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, account);
    burn_internal(asset, account, amount, false, option::some(clock::timestamp_ms(clock)));
}

public fun admin_burn<T>(
    asset: &mut Asset<T>,
    cap: &BurnCap<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    assert_cap(asset, cap.asset_id);
    burn_internal(asset, account, amount, true, option::none());
}

public fun admin_burn_with_clock<T>(
    asset: &mut Asset<T>,
    cap: &BurnCap<T>,
    account: &mut Account<T>,
    amount: u64,
    clock: &Clock,
) {
    assert_cap(asset, cap.asset_id);
    burn_internal(asset, account, amount, true, option::some(clock::timestamp_ms(clock)));
}

public fun clawback<T>(
    asset: &mut Asset<T>,
    cap: &ClawbackCap<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
) {
    clawback_internal(asset, cap, from, to, amount, option::none())
}

public fun clawback_with_clock<T>(
    asset: &mut Asset<T>,
    cap: &ClawbackCap<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    clock: &Clock,
) {
    clawback_internal(asset, cap, from, to, amount, option::some(clock::timestamp_ms(clock)))
}

fun clawback_internal<T>(
    asset: &mut Asset<T>,
    cap: &ClawbackCap<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    now_ms: Option<u64>,
) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, from);
    assert_account(asset, to);
    assert_not_frozen(to);
    assert_public_credit_allowed(asset, to, &now_ms);

    force_debit_account(asset, from, amount);
    credit_account(asset, to, amount);

    event::emit(ClawbackEvent {
        asset_id: object::id(asset),
        from_account: object::id(from),
        to_account: object::id(to),
        amount,
    });
}

public fun freeze_account<T>(asset: &Asset<T>, cap: &FreezeCap<T>, account: &mut Account<T>) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    account.frozen = true;
    event::emit(FreezeEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        frozen: true,
    });
}

public fun thaw<T>(asset: &Asset<T>, cap: &FreezeCap<T>, account: &mut Account<T>) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    account.frozen = false;
    event::emit(FreezeEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        frozen: false,
    });
}

public fun set_locked_balance<T>(
    asset: &Asset<T>,
    cap: &FreezeCap<T>,
    account: &mut Account<T>,
    locked_balance: u64,
) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    assert!(locked_balance <= account.balance, ELockedBalanceExceeded);
    account.locked_balance = locked_balance;
    event::emit(LockedBalanceUpdatedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        locked_balance,
    });
}

// === Policy / Admin ===

public fun set_kyc<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    identity: IdentityKey,
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
) {
    assert_cap(asset, cap.asset_id);
    assert_valid_identity(identity);
    assert_valid_kyc_status(status);
    assert_external_ref_hash(&external_ref_hash);

    let record = KycRecord { status, expires_ms, external_ref_hash };
    if (asset.kyc.contains(identity)) {
        *asset.kyc.borrow_mut(identity) = record;
    } else {
        asset.kyc.add(identity, record);
    };

    event::emit(KycUpdatedEvent {
        asset_id: object::id(asset),
        identity,
        status,
        expires_ms,
        external_ref_hash,
    });
}

public fun remove_kyc<T>(asset: &mut Asset<T>, cap: &PolicyCap<T>, identity: IdentityKey) {
    assert_cap(asset, cap.asset_id);
    assert_valid_identity(identity);
    if (asset.kyc.contains(identity)) {
        let _removed = asset.kyc.remove(identity);
    };
    event::emit(KycUpdatedEvent {
        asset_id: object::id(asset),
        identity,
        status: KYC_UNKNOWN,
        expires_ms: 0,
        external_ref_hash: vector[],
    });
}

public fun set_compliance_mode<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    mode: u8,
) {
    assert_cap(asset, cap.asset_id);
    assert!(asset.mode_mutable, EPolicyImmutable);
    assert_valid_mode(mode);
    asset.mode = mode;
    event::emit(ComplianceModeUpdatedEvent { asset_id: object::id(asset), mode });
}

public fun authorize_witness<T, W: drop>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
) {
    assert_cap(asset, cap.asset_id);
    set_witness_authorization<T, W>(asset, AUTH_ACTIVE);
    event::emit(WitnessAuthorizationUpdatedEvent {
        asset_id: object::id(asset),
        witness: type_name::with_original_ids<W>(),
        status: AUTH_ACTIVE,
    });
}

public fun permanently_authorize_witness<T, W: drop>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
) {
    assert_cap(asset, cap.asset_id);
    set_witness_authorization<T, W>(asset, AUTH_PERMANENT);
    event::emit(WitnessAuthorizationUpdatedEvent {
        asset_id: object::id(asset),
        witness: type_name::with_original_ids<W>(),
        status: AUTH_PERMANENT,
    });
}

public fun deauthorize_witness<T, W: drop>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
) {
    assert_cap(asset, cap.asset_id);
    let witness = type_name::with_original_ids<W>();
    if (asset.authorized_witnesses.contains(witness)) {
        assert!(*asset.authorized_witnesses.borrow(witness) != AUTH_PERMANENT, EAuthorizationPermanent);
        let _removed = asset.authorized_witnesses.remove(witness);
    };
    event::emit(WitnessAuthorizationUpdatedEvent {
        asset_id: object::id(asset),
        witness,
        status: 0,
    });
}

public fun authorize_package<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    package_addr: address,
) {
    assert_cap(asset, cap.asset_id);
    set_package_authorization(asset, package_addr, AUTH_ACTIVE);
    event::emit(PackageAuthorizationUpdatedEvent {
        asset_id: object::id(asset),
        package_addr,
        status: AUTH_ACTIVE,
    });
}

public fun permanently_authorize_package<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    package_addr: address,
) {
    assert_cap(asset, cap.asset_id);
    set_package_authorization(asset, package_addr, AUTH_PERMANENT);
    event::emit(PackageAuthorizationUpdatedEvent {
        asset_id: object::id(asset),
        package_addr,
        status: AUTH_PERMANENT,
    });
}

public fun deauthorize_package<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    package_addr: address,
) {
    assert_cap(asset, cap.asset_id);
    if (asset.authorized_packages.contains(package_addr)) {
        assert!(*asset.authorized_packages.borrow(package_addr) != AUTH_PERMANENT, EAuthorizationPermanent);
        let _removed = asset.authorized_packages.remove(package_addr);
    };
    event::emit(PackageAuthorizationUpdatedEvent {
        asset_id: object::id(asset),
        package_addr,
        status: 0,
    });
}

public fun authorize_object_holder<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    object_id: ID,
) {
    assert_cap(asset, cap.asset_id);
    set_object_authorization(asset, object_id, AUTH_ACTIVE);
    event::emit(ObjectAuthorityUpdatedEvent {
        asset_id: object::id(asset),
        object_id,
        status: AUTH_ACTIVE,
    });
}

public fun permanently_authorize_object_holder<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    object_id: ID,
) {
    assert_cap(asset, cap.asset_id);
    set_object_authorization(asset, object_id, AUTH_PERMANENT);
    event::emit(ObjectAuthorityUpdatedEvent {
        asset_id: object::id(asset),
        object_id,
        status: AUTH_PERMANENT,
    });
}

public fun deauthorize_object_holder<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    object_id: ID,
) {
    assert_cap(asset, cap.asset_id);
    if (asset.authorized_object_holders.contains(object_id)) {
        assert!(*asset.authorized_object_holders.borrow(object_id) != AUTH_PERMANENT, EAuthorizationPermanent);
        let _removed = asset.authorized_object_holders.remove(object_id);
    };
    event::emit(ObjectAuthorityUpdatedEvent {
        asset_id: object::id(asset),
        object_id,
        status: 0,
    });
}

public fun set_max_supply<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    max_supply: Option<u64>,
) {
    // This is mutable issuer policy, not a one-way ratchet. Issuers may remove
    // and reintroduce caps as part of amended authorization documents.
    assert_cap(asset, cap.asset_id);
    assert!(!asset.privacy.enabled || max_supply.is_none(), EConfidentialMaxSupplyUnsupported);
    if (max_supply.is_some()) {
        assert!(*max_supply.borrow() >= asset.supply, EMaxSupplyExceeded);
    };
    asset.max_supply = max_supply;

    event::emit(MaxSupplyUpdatedEvent {
        asset_id: object::id(asset),
        max_supply,
    });
}

public fun set_shareholder_caps<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    max_shareholders: Option<u64>,
) {
    assert_cap(asset, cap.asset_id);
    assert!(!asset.privacy.enabled || max_shareholders.is_none(), EConfidentialShareholderCapsUnsupported);
    assert_shareholder_cap(asset.total_shareholders, max_shareholders);
    asset.max_shareholders = max_shareholders;

    event::emit(ShareholderCapsUpdatedEvent {
        asset_id: object::id(asset),
        max_shareholders,
    });
}

public fun add_transfer_rule<T, Rule: drop>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
) {
    assert_cap(asset, cap.asset_id);
    let rule = type_name::with_original_ids<Rule>();
    if (!asset.transfer_rules.contains(&rule)) {
        asset.transfer_rules.insert(rule);
    };

    event::emit(TransferRuleUpdatedEvent {
        asset_id: object::id(asset),
        rule,
        enabled: true,
    });
}

public fun remove_transfer_rule<T, Rule: drop>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
) {
    assert_cap(asset, cap.asset_id);
    let rule = type_name::with_original_ids<Rule>();
    if (asset.transfer_rules.contains(&rule)) {
        asset.transfer_rules.remove(&rule);
    };

    event::emit(TransferRuleUpdatedEvent {
        asset_id: object::id(asset),
        rule,
        enabled: false,
    });
}

public fun set_fee_config<T>(
    asset: &mut Asset<T>,
    cap: &FeeCap<T>,
    bps: u64,
    fixed: u64,
    receiver: Option<ID>,
) {
    assert_cap(asset, cap.asset_id);
    assert!(bps <= MAX_BPS, EInvalidFee);
    if (bps > 0 || fixed > 0) {
        assert!(receiver.is_some(), EFeeReceiverRequired);
    };
    asset.fee = FeeConfig { bps, fixed, receiver };

    event::emit(FeeConfigUpdatedEvent {
        asset_id: object::id(asset),
        bps,
        fixed,
        receiver,
    });
}

public fun set_metadata<T>(
    asset: &mut Asset<T>,
    cap: &MetadataCap<T>,
    symbol: String,
    name: String,
    description: String,
    icon_url: String,
) {
    assert_cap(asset, cap.asset_id);
    asset.symbol = symbol;
    asset.name = name;
    asset.description = description;
    asset.icon_url = icon_url;

    event::emit(MetadataUpdatedEvent {
        asset_id: object::id(asset),
        symbol,
        name,
        description,
        icon_url,
    });
}

public fun set_metadata_pointer<T>(
    asset: &mut Asset<T>,
    cap: &MetadataCap<T>,
    metadata_pointer: Option<ID>,
) {
    assert_cap(asset, cap.asset_id);
    asset.metadata_pointer = metadata_pointer;

    event::emit(MetadataPointerUpdatedEvent {
        asset_id: object::id(asset),
        metadata_pointer,
    });
}

public fun set_group_pointers<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    group_pointer: Option<ID>,
    group_member_pointer: Option<ID>,
) {
    assert_cap(asset, cap.asset_id);
    asset.group_pointer = group_pointer;
    asset.group_member_pointer = group_member_pointer;

    event::emit(GroupPointersUpdatedEvent {
        asset_id: object::id(asset),
        group_pointer,
        group_member_pointer,
    });
}

public fun pause<T>(asset: &mut Asset<T>, cap: &PauseCap<T>) {
    assert_cap(asset, cap.asset_id);
    asset.paused = true;
    event::emit(PauseEvent { asset_id: object::id(asset), paused: true });
}

public fun unpause<T>(asset: &mut Asset<T>, cap: &PauseCap<T>) {
    assert_cap(asset, cap.asset_id);
    asset.paused = false;
    event::emit(PauseEvent { asset_id: object::id(asset), paused: false });
}

public fun set_default_account_frozen<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    frozen: bool,
) {
    assert_cap(asset, cap.asset_id);
    asset.default_account_frozen = frozen;
    event::emit(DefaultAccountStateUpdatedEvent { asset_id: object::id(asset), frozen });
}

public fun enable_non_transferable<T>(asset: &mut Asset<T>, cap: &PolicyCap<T>) {
    assert_cap(asset, cap.asset_id);
    asset.non_transferable = true;
    event::emit(NonTransferableEvent { asset_id: object::id(asset) });
}

public fun set_display_scale<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    numerator: u64,
    denominator: u64,
) {
    assert_cap(asset, cap.asset_id);
    assert_valid_display_scale(numerator, denominator);
    let _display_supply = scaled_u64(asset.supply, numerator, denominator);
    asset.display_scale_numerator = numerator;
    asset.display_scale_denominator = denominator;

    event::emit(DisplayScaleUpdatedEvent {
        asset_id: object::id(asset),
        numerator,
        denominator,
    });
}

public fun set_scaled_ui_amount<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    numerator: u64,
    denominator: u64,
) {
    set_display_scale(asset, cap, numerator, denominator);
}

public fun set_viewer_policy_hash<T>(
    asset: &mut Asset<T>,
    cap: &PolicyCap<T>,
    viewer_policy_hash: vector<u8>,
) {
    assert_cap(asset, cap.asset_id);
    assert_vector_size(&viewer_policy_hash, MAX_VIEWER_POLICY_HASH_BYTES);
    asset.privacy.viewer_policy_hash = viewer_policy_hash;
    event::emit(ViewerPolicyUpdatedEvent {
        asset_id: object::id(asset),
        viewer_policy_hash,
    });
}

public fun close_mint<T>(asset: &mut Asset<T>, cap: &CloseMintCap<T>) {
    assert_cap(asset, cap.asset_id);
    asset.mint_closed = true;
    event::emit(MintClosedEvent { asset_id: object::id(asset) });
}

public fun set_account_flags<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    account: &mut Account<T>,
    memo_required: bool,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    account.memo_required = memo_required;
    account.allow_public_credits = allow_public_credits;
    account.allow_confidential_credits = allow_confidential_credits;
    event::emit(AccountFlagsUpdatedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        memo_required,
        allow_public_credits,
        allow_confidential_credits,
    });
}

public fun set_confidential_pending_limit<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    max_pending_notes: u64,
    ctx: &TxContext,
) {
    assert_owner_authorized(account, ctx);
    set_confidential_pending_limit_internal(asset, account, max_pending_notes)
}

public fun set_confidential_credits_enabled<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    enabled: bool,
    ctx: &TxContext,
) {
    assert_owner_authorized(account, ctx);
    set_confidential_credits_enabled_internal(asset, account, enabled)
}

public fun set_confidential_credits_enabled_with_object_authority<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    account: &mut Account<T>,
    enabled: bool,
) {
    assert_object_authorized(asset, authority, account);
    set_confidential_credits_enabled_internal(asset, account, enabled)
}

public fun set_confidential_credits_enabled_with_package_witness<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    account: &mut Account<T>,
    enabled: bool,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, account);
    set_confidential_credits_enabled_internal(asset, account, enabled)
}

public fun admin_set_confidential_pending_limit<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    account: &mut Account<T>,
    max_pending_notes: u64,
) {
    assert_cap(asset, cap.asset_id);
    set_confidential_pending_limit_internal(asset, account, max_pending_notes)
}

public fun lock_owner<T>(asset: &Asset<T>, cap: &RegistrationCap<T>, account: &mut Account<T>) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    account.immutable_owner = true;
    event::emit(OwnerLockedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
    });
}

public fun set_holder<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    holder: HolderKey,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    reason_hash: vector<u8>,
) {
    set_holder_internal(
        asset,
        cap,
        account,
        holder,
        owner_encrypted_opening,
        encrypted_openings_for_viewers,
        reason_hash,
        option::none(),
    )
}

public fun set_identity<T>(
    asset: &mut Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    identity: IdentityKey,
    reason_hash: vector<u8>,
) {
    set_identity_internal(asset, cap, account, identity, reason_hash, option::none())
}

public fun set_identity_with_clock<T>(
    asset: &mut Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    identity: IdentityKey,
    reason_hash: vector<u8>,
    clock: &Clock,
) {
    set_identity_internal(
        asset,
        cap,
        account,
        identity,
        reason_hash,
        option::some(clock::timestamp_ms(clock)),
    )
}

public fun set_holder_with_clock<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    holder: HolderKey,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    reason_hash: vector<u8>,
    clock: &Clock,
) {
    set_holder_internal(
        asset,
        cap,
        account,
        holder,
        owner_encrypted_opening,
        encrypted_openings_for_viewers,
        reason_hash,
        option::some(clock::timestamp_ms(clock)),
    )
}

fun set_holder_internal<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    holder: HolderKey,
    owner_encrypted_opening: vector<u8>,
    encrypted_openings_for_viewers: vector<vector<u8>>,
    reason_hash: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    assert!(!account.immutable_owner, EImmutableOwner);
    assert_no_pending_confidential(account);
    assert_valid_holder(holder);
    assert_vector_size(&reason_hash, MAX_EXTERNAL_REF_HASH_BYTES);
    assert_opening_bytes(&owner_encrypted_opening);
    assert_opening_bytes_vector(&encrypted_openings_for_viewers);
    let _ = now_ms;
    account.holder = holder;
    account.confidential.encrypted_available_for_owner = owner_encrypted_opening;
    account.confidential.encrypted_available_for_viewers = encrypted_openings_for_viewers;
    clear_pending_confidential_notes(account);
    event::emit(HolderUpdatedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        holder,
        reason_hash,
    });
}

fun set_identity_internal<T>(
    asset: &mut Asset<T>,
    cap: &RegistrationCap<T>,
    account: &mut Account<T>,
    identity: IdentityKey,
    reason_hash: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_cap(asset, cap.asset_id);
    assert_account(asset, account);
    assert_valid_identity(identity);
    assert_vector_size(&reason_hash, MAX_EXTERNAL_REF_HASH_BYTES);
    assert_identity_allowed(asset, identity, &now_ms);
    let previous_identity = account.identity;
    if (account.balance > 0 && previous_identity != identity) {
        unregister_positive_account(asset, previous_identity);
        register_positive_account(asset, identity);
    };
    account.identity = identity;
    event::emit(IdentityUpdatedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        identity,
        reason_hash,
    });
}

public fun set_available_openings<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
    ctx: &TxContext,
) {
    assert_privacy_enabled(asset);
    assert_account(asset, account);
    assert_owner_authorized(account, ctx);
    assert_opening_bytes(&encrypted_available_for_owner);
    assert_opening_bytes_vector(&encrypted_available_for_viewers);
    account.confidential.encrypted_available_for_owner = encrypted_available_for_owner;
    account.confidential.encrypted_available_for_viewers = encrypted_available_for_viewers;
}

public fun admin_set_available_openings<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    account: &mut Account<T>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
) {
    assert_cap(asset, cap.asset_id);
    assert_privacy_enabled(asset);
    assert_account(asset, account);
    assert_opening_bytes(&encrypted_available_for_owner);
    assert_opening_bytes_vector(&encrypted_available_for_viewers);
    account.confidential.encrypted_available_for_owner = encrypted_available_for_owner;
    account.confidential.encrypted_available_for_viewers = encrypted_available_for_viewers;
}

// === Confidential Operations ===

public fun confidential_mint<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    supply_new_commitment_bytes: vector<u8>,
    range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    supply_new_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
) {
    confidential_mint_internal(
        asset,
        cap,
        to,
        amount_commitment_bytes,
        recipient_new_pending_bytes,
        supply_new_commitment_bytes,
        range_proof,
        recipient_pending_range_proof,
        supply_new_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        option::none(),
    )
}

public fun confidential_mint_with_clock<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    supply_new_commitment_bytes: vector<u8>,
    range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    supply_new_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    clock: &Clock,
) {
    confidential_mint_internal(
        asset,
        cap,
        to,
        amount_commitment_bytes,
        recipient_new_pending_bytes,
        supply_new_commitment_bytes,
        range_proof,
        recipient_pending_range_proof,
        supply_new_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        option::some(clock::timestamp_ms(clock)),
    )
}

fun confidential_mint_internal<T>(
    asset: &mut Asset<T>,
    cap: &MintCap<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    supply_new_commitment_bytes: vector<u8>,
    range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    supply_new_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    now_ms: Option<u64>,
) {
    // Pause is a movement halt. Issuers may still mint during a paused
    // corporate action or incident workflow.
    assert_cap(asset, cap.asset_id);
    assert!(!asset.mint_closed, EMintClosed);
    assert_privacy_enabled(asset);
    assert_confidential_allowed_with_shareholder_caps(asset);
    assert_account(asset, to);
    assert_not_frozen(to);
    assert_confidential_credit_allowed(asset, to, &now_ms);
    assert_pending_note_capacity(to);
    assert_encrypted_note(&encrypted_note_for_recipient);
    assert_encrypted_notes_for_viewers(&encrypted_notes_for_viewers);

    let amount_commitment = commitment_from_bytes(amount_commitment_bytes);
    let recipient_new_pending = commitment_from_bytes(recipient_new_pending_bytes);
    let supply_new_commitment = commitment_from_bytes(supply_new_commitment_bytes);

    assert!(
        group_ops::equal(
            &recipient_new_pending,
            &ristretto255::g_add(&to.confidential.pending, &amount_commitment),
        ),
        EInvalidCommitment,
    );
    assert!(
        group_ops::equal(
            &supply_new_commitment,
            &ristretto255::g_add(&asset.privacy.confidential_supply_commitment, &amount_commitment),
        ),
        EInvalidCommitment,
    );
    verify_range(amount_commitment, range_proof);
    verify_range(recipient_new_pending, recipient_pending_range_proof);
    verify_range(supply_new_commitment, supply_new_range_proof);

    to.confidential.pending = recipient_new_pending;
    push_pending_confidential_note(to, encrypted_note_for_recipient, encrypted_notes_for_viewers);
    asset.privacy.confidential_supply_commitment = supply_new_commitment;

    event::emit(ConfidentialMintEvent {
        asset_id: object::id(asset),
        account_id: object::id(to),
        amount_commitment,
    });
}

public fun confidential_transfer<T>(
    asset: &Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    ctx: &TxContext,
) {
    assert_owner_authorized(from, ctx);
    confidential_transfer_internal(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::none(),
    );
}

public fun confidential_transfer_with_clock<T>(
    asset: &Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
) {
    assert_owner_authorized(from, ctx);
    confidential_transfer_internal(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::some(clock::timestamp_ms(clock)),
    );
}

public fun confidential_transfer_with_object_authority<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
) {
    assert_object_authorized(asset, authority, from);
    confidential_transfer_internal(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::none(),
    );
}

public fun confidential_transfer_with_object_authority_and_clock<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    clock: &Clock,
) {
    assert_object_authorized(asset, authority, from);
    confidential_transfer_internal(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::some(clock::timestamp_ms(clock)),
    );
}

public fun confidential_transfer_with_package_witness<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    confidential_transfer_internal(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::none(),
    );
}

public fun confidential_transfer_with_package_witness_and_clock<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    clock: &Clock,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    confidential_transfer_internal(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::some(clock::timestamp_ms(clock)),
    );
}

public fun request_confidential_transfer<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    ctx: &TxContext,
): ConfidentialTransferRequest<T> {
    assert_owner_authorized(from, ctx);
    new_confidential_transfer_request(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::none(),
    )
}

public fun request_confidential_transfer_with_clock<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    clock: &Clock,
    ctx: &TxContext,
): ConfidentialTransferRequest<T> {
    assert_owner_authorized(from, ctx);
    new_confidential_transfer_request(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::some(clock::timestamp_ms(clock)),
    )
}

public fun request_confidential_transfer_with_object_authority<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
): ConfidentialTransferRequest<T> {
    assert_object_authorized(asset, authority, from);
    new_confidential_transfer_request(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::none(),
    )
}

public fun request_confidential_transfer_with_object_authority_and_clock<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    clock: &Clock,
): ConfidentialTransferRequest<T> {
    assert_object_authorized(asset, authority, from);
    new_confidential_transfer_request(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::some(clock::timestamp_ms(clock)),
    )
}

public fun request_confidential_transfer_with_package_witness<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
): ConfidentialTransferRequest<T> {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    new_confidential_transfer_request(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::none(),
    )
}

public fun request_confidential_transfer_with_package_witness_and_clock<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    clock: &Clock,
): ConfidentialTransferRequest<T> {
    let _ = witness;
    assert_package_authorized<T, W>(asset, from);
    new_confidential_transfer_request(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        option::some(clock::timestamp_ms(clock)),
    )
}

public fun add_confidential_transfer_rule_approval<T, Rule: drop>(
    _rule: Rule,
    request: &mut ConfidentialTransferRequest<T>,
) {
    request.approvals.insert(type_name::with_original_ids<Rule>());
}

public fun confirm_confidential_transfer<T>(
    asset: &Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    request: ConfidentialTransferRequest<T>,
) {
    let ConfidentialTransferRequest {
        asset_id,
        from_account,
        to_account,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        now_ms,
        approvals,
    } = request;

    assert!(asset_id == object::id(asset), ETransferRequestMismatch);
    assert!(from_account == object::id(from), ETransferRequestMismatch);
    assert!(to_account == object::id(to), ETransferRequestMismatch);
    assert_transfer_rule_approvals(asset, &approvals);

    confidential_transfer_internal_after_rules(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        now_ms,
    );
}

public fun confidential_burn<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    account_new_available_bytes: vector<u8>,
    supply_new_commitment_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    account_new_range_proof: vector<u8>,
    supply_new_range_proof: vector<u8>,
    ctx: &TxContext,
) {
    assert_owner_authorized(account, ctx);
    confidential_burn_internal(
        asset,
        account,
        amount_commitment_bytes,
        account_new_available_bytes,
        supply_new_commitment_bytes,
        amount_range_proof,
        account_new_range_proof,
        supply_new_range_proof,
        false,
    );
}

public fun admin_confidential_burn<T>(
    asset: &mut Asset<T>,
    cap: &BurnCap<T>,
    account: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    account_new_available_bytes: vector<u8>,
    supply_new_commitment_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    account_new_range_proof: vector<u8>,
    supply_new_range_proof: vector<u8>,
) {
    assert_cap(asset, cap.asset_id);
    confidential_burn_internal(
        asset,
        account,
        amount_commitment_bytes,
        account_new_available_bytes,
        supply_new_commitment_bytes,
        amount_range_proof,
        account_new_range_proof,
        supply_new_range_proof,
        true,
    );
}

public fun apply_pending_confidential<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    new_available_bytes: vector<u8>,
    range_proof: vector<u8>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
    ctx: &TxContext,
) {
    assert_owner_authorized(account, ctx);
    apply_pending_confidential_internal(
        asset,
        account,
        new_available_bytes,
        range_proof,
        encrypted_available_for_owner,
        encrypted_available_for_viewers,
        true,
    );
}

public fun apply_pending_confidential_with_object_authority<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    account: &mut Account<T>,
    new_available_bytes: vector<u8>,
    range_proof: vector<u8>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
) {
    assert_object_authorized(asset, authority, account);
    apply_pending_confidential_internal(
        asset,
        account,
        new_available_bytes,
        range_proof,
        encrypted_available_for_owner,
        encrypted_available_for_viewers,
        true,
    );
}

public fun apply_pending_confidential_with_package_witness<T, W: drop>(
    asset: &Asset<T>,
    witness: W,
    account: &mut Account<T>,
    new_available_bytes: vector<u8>,
    range_proof: vector<u8>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
) {
    let _ = witness;
    assert_package_authorized<T, W>(asset, account);
    apply_pending_confidential_internal(
        asset,
        account,
        new_available_bytes,
        range_proof,
        encrypted_available_for_owner,
        encrypted_available_for_viewers,
        true,
    );
}

public fun admin_apply_pending_confidential<T>(
    asset: &Asset<T>,
    cap: &PolicyCap<T>,
    account: &mut Account<T>,
    new_available_bytes: vector<u8>,
    range_proof: vector<u8>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
) {
    assert_cap(asset, cap.asset_id);
    apply_pending_confidential_internal(
        asset,
        account,
        new_available_bytes,
        range_proof,
        encrypted_available_for_owner,
        encrypted_available_for_viewers,
        false,
    );
}

// === Views ===

public fun holder_address(addr: address): HolderKey {
    HolderKey { kind: HOLDER_ADDRESS, addr }
}

public fun holder_object(id: ID): HolderKey {
    // Only use object holders with owned authority objects or shared objects whose
    // module gates transfer calls. A public shared object reference is sufficient
    // authority for this account.
    HolderKey { kind: HOLDER_OBJECT, addr: object::id_to_address(&id) }
}

public fun holder_package(package_addr: address): HolderKey {
    HolderKey { kind: HOLDER_PACKAGE, addr: package_addr }
}

public fun identity_address(addr: address): IdentityKey {
    IdentityKey { kind: IDENTITY_ADDRESS, addr }
}

public fun identity_object(id: ID): IdentityKey {
    IdentityKey { kind: IDENTITY_OBJECT, addr: object::id_to_address(&id) }
}

public fun identity_external(addr: address): IdentityKey {
    // Opaque issuer/offchain-registry identity key. This may be a hash-derived
    // address and does not need to be a wallet address.
    IdentityKey { kind: IDENTITY_EXTERNAL, addr }
}

public fun identity_from_holder(holder: HolderKey): IdentityKey {
    let kind = if (holder.kind == HOLDER_ADDRESS) {
        IDENTITY_ADDRESS
    } else if (holder.kind == HOLDER_OBJECT) {
        IDENTITY_OBJECT
    } else if (holder.kind == HOLDER_PACKAGE) {
        IDENTITY_EXTERNAL
    } else {
        abort EInvalidHolderKind
    };
    IdentityKey { kind, addr: holder.addr }
}

public fun allowlist_mode(): u8 { MODE_ALLOWLIST }
public fun denylist_mode(): u8 { MODE_DENYLIST }
public fun open_mode(): u8 { MODE_OPEN }

public fun kyc_unknown(): u8 { KYC_UNKNOWN }
public fun kyc_approved(): u8 { KYC_APPROVED }
public fun kyc_denied(): u8 { KYC_DENIED }
public fun kyc_pending(): u8 { KYC_PENDING }
public fun kyc_expired(): u8 { KYC_EXPIRED }
public fun kyc_exempt(): u8 { KYC_EXEMPT }

public fun asset_id<T>(asset: &Asset<T>): ID { object::id(asset) }
public fun account_id<T>(account: &Account<T>): ID { object::id(account) }
public fun receipt_account_id<T>(receipt: &Receipt<T>): ID { receipt.account_id }
public fun receipt_asset_id<T>(receipt: &Receipt<T>): ID { receipt.asset_id }
public fun symbol<T>(asset: &Asset<T>): String { asset.symbol }
public fun name<T>(asset: &Asset<T>): String { asset.name }
public fun description<T>(asset: &Asset<T>): String { asset.description }
public fun icon_url<T>(asset: &Asset<T>): String { asset.icon_url }
public fun decimals<T>(asset: &Asset<T>): u8 { asset.decimals }
public fun holder<T>(account: &Account<T>): HolderKey { account.holder }
public fun account_identity<T>(account: &Account<T>): IdentityKey { account.identity }
public fun balance<T>(account: &Account<T>): u64 { account.balance }
public fun supply<T>(asset: &Asset<T>): u64 { asset.supply }
public fun max_supply<T>(asset: &Asset<T>): Option<u64> { asset.max_supply }
public fun total_shareholders<T>(asset: &Asset<T>): u64 { asset.total_shareholders }
public fun shareholder_cap<T>(asset: &Asset<T>): Option<u64> { asset.max_shareholders }
public fun identity_positive_account_count<T>(asset: &Asset<T>, identity: IdentityKey): u64 {
    if (asset.shareholder_accounts.contains(identity)) {
        *asset.shareholder_accounts.borrow(identity)
    } else {
        0
    }
}
public fun raw_balance<T>(account: &Account<T>): u64 { account.balance }
public fun raw_supply<T>(asset: &Asset<T>): u64 { asset.supply }
public fun locked_balance<T>(account: &Account<T>): u64 { account.locked_balance }
public fun restricted_lot_count<T>(account: &Account<T>): u64 {
    account.restricted_lots.length()
}
public fun restricted_lots<T>(account: &Account<T>): vector<RestrictedLot> {
    account.restricted_lots
}
public fun restricted_locked_balance<T>(account: &Account<T>): u64 {
    let now_ms = option::none();
    restricted_locked_balance_internal(account, &now_ms)
}
public fun restricted_locked_balance_with_clock<T>(account: &Account<T>, clock: &Clock): u64 {
    let now_ms = option::some(clock::timestamp_ms(clock));
    restricted_locked_balance_internal(account, &now_ms)
}
public fun transferable_balance<T>(account: &Account<T>): u64 {
    let now_ms = option::none();
    available_transferable_balance(account, &now_ms)
}
public fun transferable_balance_with_clock<T>(account: &Account<T>, clock: &Clock): u64 {
    let now_ms = option::some(clock::timestamp_ms(clock));
    available_transferable_balance(account, &now_ms)
}
public fun display_balance<T>(asset: &Asset<T>, account: &Account<T>): u64 {
    assert_account(asset, account);
    scaled_u64(account.balance, asset.display_scale_numerator, asset.display_scale_denominator)
}
public fun display_supply<T>(asset: &Asset<T>): u64 {
    scaled_u64(asset.supply, asset.display_scale_numerator, asset.display_scale_denominator)
}
public fun display_scale<T>(asset: &Asset<T>): (u64, u64) {
    (asset.display_scale_numerator, asset.display_scale_denominator)
}
public fun metadata_pointer<T>(asset: &Asset<T>): Option<ID> { asset.metadata_pointer }
public fun group_pointer<T>(asset: &Asset<T>): Option<ID> { asset.group_pointer }
public fun group_member_pointer<T>(asset: &Asset<T>): Option<ID> { asset.group_member_pointer }
public fun paused<T>(asset: &Asset<T>): bool { asset.paused }
public fun default_account_frozen<T>(asset: &Asset<T>): bool { asset.default_account_frozen }
public fun non_transferable<T>(asset: &Asset<T>): bool { asset.non_transferable }
public fun mode<T>(asset: &Asset<T>): u8 { asset.mode }
public fun frozen<T>(account: &Account<T>): bool { account.frozen }
public fun transfer_rule_count<T>(asset: &Asset<T>): u64 { asset.transfer_rules.length() }
public fun has_transfer_rule<T, Rule: drop>(asset: &Asset<T>): bool {
    asset.transfer_rules.contains(&type_name::with_original_ids<Rule>())
}
public fun transfer_request_asset_id<T>(request: &TransferRequest<T>): ID { request.asset_id }
public fun transfer_request_from_account<T>(request: &TransferRequest<T>): ID { request.from_account }
public fun transfer_request_to_account<T>(request: &TransferRequest<T>): ID { request.to_account }
public fun transfer_request_fee_account<T>(request: &TransferRequest<T>): Option<ID> {
    request.fee_account
}
public fun transfer_request_amount<T>(request: &TransferRequest<T>): u64 { request.amount }
public fun transfer_request_memo<T>(request: &TransferRequest<T>): vector<u8> { request.memo }
public fun pending_confidential_note_count<T>(account: &Account<T>): u64 {
    account.confidential.pending_note_count
}
public fun pending_confidential_note<T>(account: &Account<T>, index: u64): PendingEncryptedNote {
    *account.confidential.encrypted_pending_notes.borrow(index)
}
public fun pending_note_recipient_note(note: &PendingEncryptedNote): vector<u8> {
    note.recipient_note
}
public fun pending_note_viewer_notes(note: &PendingEncryptedNote): vector<vector<u8>> {
    note.viewer_notes
}
public fun max_pending_confidential_notes(): u64 { MAX_PENDING_CONFIDENTIAL_NOTES }
public fun account_max_pending_confidential_notes<T>(account: &Account<T>): u64 {
    account.confidential.max_pending_notes
}
public fun confidential_available<T>(account: &Account<T>): Element<ristretto255::G> {
    account.confidential.available
}
public fun confidential_pending<T>(account: &Account<T>): Element<ristretto255::G> {
    account.confidential.pending
}
public fun confidential_enabled<T>(account: &Account<T>): bool {
    account.confidential.enabled
}
public fun confidential_supply<T>(asset: &Asset<T>): Element<ristretto255::G> {
    asset.privacy.confidential_supply_commitment
}
public fun viewer_policy_hash<T>(asset: &Asset<T>): vector<u8> {
    asset.privacy.viewer_policy_hash
}

// === Test Helpers ===

#[test_only]
public fun new_asset_for_testing<T>(
    mode: u8,
    privacy_enabled: bool,
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
    assert_valid_mode(mode);
    let asset_uid = object::new(ctx);
    let asset_id = object::uid_to_inner(&asset_uid);
    (
        Asset<T> {
            id: asset_uid,
            symbol: b"RT".to_string(),
            name: b"Regulated Account".to_string(),
            description: b"Regulated token test asset".to_string(),
            icon_url: b"https://example.com/rt.png".to_string(),
            decimals: 9,
            supply: 0,
            max_supply: option::none(),
            total_shareholders: 0,
            max_shareholders: option::none(),
            display_scale_numerator: 1,
            display_scale_denominator: 1,
            metadata_pointer: option::none(),
            group_pointer: option::none(),
            group_member_pointer: option::none(),
            mode,
            mode_mutable: true,
            mint_closed: false,
            paused: false,
            default_account_frozen: false,
            non_transferable: false,
            fee: FeeConfig { bps: 0, fixed: 0, receiver: option::none() },
            privacy: PrivacyConfig {
                enabled: privacy_enabled,
                viewer_policy_hash: vector[],
                confidential_supply_commitment: ristretto255::g_identity(),
            },
            kyc: table::new(ctx),
            shareholder_accounts: table::new(ctx),
            transfer_rules: vec_set::empty(),
            authorized_witnesses: table::new(ctx),
            authorized_packages: table::new(ctx),
            authorized_object_holders: table::new(ctx),
        },
        MintCap<T> { id: object::new(ctx), asset_id },
        PolicyCap<T> { id: object::new(ctx), asset_id },
        FreezeCap<T> { id: object::new(ctx), asset_id },
        BurnCap<T> { id: object::new(ctx), asset_id },
        ClawbackCap<T> { id: object::new(ctx), asset_id },
        FeeCap<T> { id: object::new(ctx), asset_id },
        CloseMintCap<T> { id: object::new(ctx), asset_id },
    )
}

#[test_only]
public fun new_metadata_cap_for_testing<T>(asset: &Asset<T>, ctx: &mut TxContext): MetadataCap<T> {
    MetadataCap<T> { id: object::new(ctx), asset_id: object::id(asset) }
}

#[test_only]
public fun new_pause_cap_for_testing<T>(asset: &Asset<T>, ctx: &mut TxContext): PauseCap<T> {
    PauseCap<T> { id: object::new(ctx), asset_id: object::id(asset) }
}

#[test_only]
public fun new_registration_cap_for_testing<T>(
    asset: &Asset<T>,
    ctx: &mut TxContext,
): RegistrationCap<T> {
    RegistrationCap<T> { id: object::new(ctx), asset_id: object::id(asset) }
}

#[test_only]
public fun add_pending_note_for_testing<T>(
    account: &mut Account<T>,
    note: vector<u8>,
    viewer_notes: vector<vector<u8>>,
) {
    assert_pending_note_capacity(account);
    account.confidential.pending = ristretto255::g_generator();
    push_pending_confidential_note(account, note, viewer_notes);
}

#[test_only]
public fun new_account_for_testing<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    ctx: &mut TxContext,
): Account<T> {
    new_account_for_testing_with_identity(
        asset,
        holder,
        identity_from_holder(holder),
        allow_public_credits,
        allow_confidential_credits,
        ctx,
    )
}

#[test_only]
public fun new_account_for_testing_with_identity<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    ctx: &mut TxContext,
): Account<T> {
    assert_valid_holder(holder);
    assert_valid_identity(identity);
    let now_ms = option::none();
    assert_identity_allowed(asset, identity, &now_ms);
    Account<T> {
        id: object::new(ctx),
        asset_id: object::id(asset),
        holder,
        identity,
        balance: 0,
        locked_balance: 0,
        restricted_lots: vector[],
        frozen: asset.default_account_frozen,
        immutable_owner: false,
        memo_required: false,
        allow_public_credits,
        allow_confidential_credits,
        confidential: ConfidentialBalance {
            enabled: asset.privacy.enabled,
            available: ristretto255::g_identity(),
            pending: ristretto255::g_identity(),
            encrypted_available_for_owner: vector[],
            encrypted_available_for_viewers: vector[],
            encrypted_pending_notes: table::new(ctx),
            pending_note_count: 0,
            max_pending_notes: MAX_PENDING_CONFIDENTIAL_NOTES,
        },
    }
}

#[test_only]
public fun new_account_for_testing_with_clock<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): Account<T> {
    new_account_for_testing_with_identity_and_clock(
        asset,
        holder,
        identity_from_holder(holder),
        allow_public_credits,
        allow_confidential_credits,
        clock,
        ctx,
    )
}

#[test_only]
public fun new_account_for_testing_with_identity_and_clock<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    allow_public_credits: bool,
    allow_confidential_credits: bool,
    clock: &Clock,
    ctx: &mut TxContext,
): Account<T> {
    assert_valid_holder(holder);
    assert_valid_identity(identity);
    let now_ms = option::some(clock::timestamp_ms(clock));
    assert_identity_allowed(asset, identity, &now_ms);
    Account<T> {
        id: object::new(ctx),
        asset_id: object::id(asset),
        holder,
        identity,
        balance: 0,
        locked_balance: 0,
        restricted_lots: vector[],
        frozen: asset.default_account_frozen,
        immutable_owner: false,
        memo_required: false,
        allow_public_credits,
        allow_confidential_credits,
        confidential: ConfidentialBalance {
            enabled: asset.privacy.enabled,
            available: ristretto255::g_identity(),
            pending: ristretto255::g_identity(),
            encrypted_available_for_owner: vector[],
            encrypted_available_for_viewers: vector[],
            encrypted_pending_notes: table::new(ctx),
            pending_note_count: 0,
            max_pending_notes: MAX_PENDING_CONFIDENTIAL_NOTES,
        },
    }
}

// === Internal Helpers ===

fun new_transfer_request<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    fee_account: Option<ID>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
): TransferRequest<T> {
    assert_account(asset, from);
    assert_account(asset, to);
    if (fee_account.is_some()) {
        assert!(asset.fee.receiver.is_some(), EFeeReceiverRequired);
        assert!(*fee_account.borrow() == *asset.fee.receiver.borrow(), EFeeReceiverRequired);
    };

    TransferRequest<T> {
        asset_id: object::id(asset),
        from_account: object::id(from),
        to_account: object::id(to),
        fee_account,
        amount,
        memo,
        now_ms,
        approvals: vec_set::empty(),
    }
}

fun new_confidential_transfer_request<T>(
    asset: &Asset<T>,
    from: &Account<T>,
    to: &Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    now_ms: Option<u64>,
): ConfidentialTransferRequest<T> {
    assert_account(asset, from);
    assert_account(asset, to);

    ConfidentialTransferRequest<T> {
        asset_id: object::id(asset),
        from_account: object::id(from),
        to_account: object::id(to),
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        now_ms,
        approvals: vec_set::empty(),
    }
}

fun confirm_transfer_request<T>(
    asset: &Asset<T>,
    from_account: ID,
    to_account: ID,
    fee_account: Option<ID>,
    request: TransferRequest<T>,
): (u64, vector<u8>, Option<u64>) {
    let TransferRequest {
        asset_id,
        from_account: request_from,
        to_account: request_to,
        fee_account: request_fee_account,
        amount,
        memo,
        now_ms,
        approvals,
    } = request;

    assert!(asset_id == object::id(asset), ETransferRequestMismatch);
    assert!(request_from == from_account, ETransferRequestMismatch);
    assert!(request_to == to_account, ETransferRequestMismatch);
    assert!(request_fee_account == fee_account, ETransferRequestMismatch);
    assert_transfer_rule_approvals(asset, &approvals);

    (amount, memo, now_ms)
}

fun transfer_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_no_transfer_rules(asset);
    transfer_internal_after_rules(asset, from, to, amount, memo, now_ms);
}

fun transfer_internal_after_rules<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_not_paused(asset);
    assert_transferable(asset);
    assert_account(asset, from);
    assert_account(asset, to);
    assert_not_frozen(from);
    assert_not_frozen(to);
    assert_public_debit_allowed(asset, from, &now_ms);
    assert_public_credit_allowed(asset, to, &now_ms);
    assert_memo(to, &memo);
    prepare_transferable_debit(from, amount, &now_ms);

    let fee_amount = compute_fee(&asset.fee, amount);
    assert!(fee_amount == 0, EUseTransferWithFee);
    assert!(amount >= fee_amount, EInvalidFee);
    let net_amount = amount - fee_amount;

    debit_account(asset, from, amount);
    credit_account(asset, to, net_amount);

    event::emit(TransferEvent {
        asset_id: object::id(asset),
        from_account: object::id(from),
        to_account: object::id(to),
        gross_amount: amount,
        fee_amount,
        net_amount,
        memo,
    });
}

fun transfer_with_fee_internal<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_no_transfer_rules(asset);
    transfer_with_fee_internal_after_rules(asset, from, to, fee_account, amount, memo, now_ms);
}

fun transfer_with_fee_internal_after_rules<T>(
    asset: &mut Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    fee_account: &mut Account<T>,
    amount: u64,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    // Move's borrow checker enforces that these mutable account refs are distinct.
    // Keep an explicit object-ID check if this ever moves to ID-based account lookup.
    assert_not_paused(asset);
    assert_transferable(asset);
    assert_account(asset, from);
    assert_account(asset, to);
    assert_account(asset, fee_account);
    assert_not_frozen(from);
    assert_not_frozen(to);
    assert_not_frozen(fee_account);
    assert_public_debit_allowed(asset, from, &now_ms);
    assert_public_credit_allowed(asset, to, &now_ms);
    assert_public_credit_allowed(asset, fee_account, &now_ms);
    assert_memo(to, &memo);
    prepare_transferable_debit(from, amount, &now_ms);

    let fee_amount = compute_fee(&asset.fee, amount);
    assert!(fee_amount > 0, EInvalidFee);
    assert!(asset.fee.receiver.is_some(), EFeeReceiverRequired);
    assert!(object::id(fee_account) == *asset.fee.receiver.borrow(), EFeeReceiverRequired);
    assert!(amount >= fee_amount, EInvalidFee);
    let net_amount = amount - fee_amount;

    debit_account(asset, from, amount);
    credit_account(asset, to, net_amount);
    credit_account(asset, fee_account, fee_amount);

    event::emit(TransferEvent {
        asset_id: object::id(asset),
        from_account: object::id(from),
        to_account: object::id(to),
        gross_amount: amount,
        fee_amount,
        net_amount,
        memo,
    });
}

fun burn_internal<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
    admin_burn: bool,
    now_ms: Option<u64>,
) {
    // Pause gates transfers. Burns remain available so holders/admins can
    // reduce supply during paused remediation or corporate action flows.
    assert_account(asset, account);
    if (!admin_burn) {
        assert_not_frozen(account);
        assert_public_debit_allowed(asset, account, &now_ms);
        prepare_transferable_debit(account, amount, &now_ms);
        debit_account(asset, account, amount);
    } else {
        force_debit_account(asset, account, amount);
    };
    asset.supply = asset.supply - amount;

    event::emit(BurnEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        amount,
        admin_burn,
    });
}

fun confidential_transfer_internal<T>(
    asset: &Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_no_transfer_rules(asset);
    confidential_transfer_internal_after_rules(
        asset,
        from,
        to,
        amount_commitment_bytes,
        sender_new_available_bytes,
        recipient_new_pending_bytes,
        amount_range_proof,
        sender_new_range_proof,
        recipient_pending_range_proof,
        encrypted_note_for_recipient,
        encrypted_notes_for_viewers,
        sender_encrypted_available_for_owner,
        sender_encrypted_available_for_viewers,
        memo,
        now_ms,
    );
}

fun confidential_transfer_internal_after_rules<T>(
    asset: &Asset<T>,
    from: &mut Account<T>,
    to: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    sender_new_available_bytes: vector<u8>,
    recipient_new_pending_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    sender_new_range_proof: vector<u8>,
    recipient_pending_range_proof: vector<u8>,
    encrypted_note_for_recipient: vector<u8>,
    encrypted_notes_for_viewers: vector<vector<u8>>,
    sender_encrypted_available_for_owner: vector<u8>,
    sender_encrypted_available_for_viewers: vector<vector<u8>>,
    memo: vector<u8>,
    now_ms: Option<u64>,
) {
    assert_not_paused(asset);
    assert_transferable(asset);
    assert_privacy_enabled(asset);
    assert_confidential_allowed_with_shareholder_caps(asset);
    assert_account(asset, from);
    assert_account(asset, to);
    assert_not_frozen(from);
    assert_not_frozen(to);
    assert_confidential_account_enabled(from);
    assert_confidential_debit_allowed(asset, from, &now_ms);
    assert_confidential_credit_allowed(asset, to, &now_ms);
    assert_pending_note_capacity(to);
    assert_memo(to, &memo);
    assert_encrypted_note(&encrypted_note_for_recipient);
    assert_encrypted_notes_for_viewers(&encrypted_notes_for_viewers);
    assert_opening_bytes(&sender_encrypted_available_for_owner);
    assert_opening_bytes_vector(&sender_encrypted_available_for_viewers);
    assert!(asset.fee.bps == 0 && asset.fee.fixed == 0, EConfidentialFeesUnsupported);

    let amount_commitment = commitment_from_bytes(amount_commitment_bytes);
    let sender_new_available = commitment_from_bytes(sender_new_available_bytes);
    let recipient_new_pending = commitment_from_bytes(recipient_new_pending_bytes);

    assert!(
        group_ops::equal(
            &sender_new_available,
            &ristretto255::g_sub(&from.confidential.available, &amount_commitment),
        ),
        EInvalidCommitment,
    );
    assert!(
        group_ops::equal(
            &recipient_new_pending,
            &ristretto255::g_add(&to.confidential.pending, &amount_commitment),
        ),
        EInvalidCommitment,
    );
    verify_range(amount_commitment, amount_range_proof);
    verify_range(sender_new_available, sender_new_range_proof);
    verify_range(recipient_new_pending, recipient_pending_range_proof);

    from.confidential.available = sender_new_available;
    from.confidential.encrypted_available_for_owner = sender_encrypted_available_for_owner;
    from.confidential.encrypted_available_for_viewers = sender_encrypted_available_for_viewers;
    to.confidential.pending = recipient_new_pending;
    push_pending_confidential_note(to, encrypted_note_for_recipient, encrypted_notes_for_viewers);

    event::emit(ConfidentialTransferEvent {
        asset_id: object::id(asset),
        from_account: object::id(from),
        to_account: object::id(to),
        amount_commitment,
        memo,
    });
}

fun confidential_burn_internal<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount_commitment_bytes: vector<u8>,
    account_new_available_bytes: vector<u8>,
    supply_new_commitment_bytes: vector<u8>,
    amount_range_proof: vector<u8>,
    account_new_range_proof: vector<u8>,
    supply_new_range_proof: vector<u8>,
    admin_burn: bool,
) {
    assert_privacy_enabled(asset);
    assert_confidential_allowed_with_shareholder_caps(asset);
    assert_account(asset, account);
    if (!admin_burn) {
        assert_not_frozen(account);
    };
    assert_confidential_account_enabled(account);
    if (!admin_burn) {
        let now_ms = option::none();
        assert_confidential_debit_allowed(asset, account, &now_ms);
    };

    let amount_commitment = commitment_from_bytes(amount_commitment_bytes);
    let account_new_available = commitment_from_bytes(account_new_available_bytes);
    let supply_new_commitment = commitment_from_bytes(supply_new_commitment_bytes);

    assert!(
        group_ops::equal(
            &account_new_available,
            &ristretto255::g_sub(&account.confidential.available, &amount_commitment),
        ),
        EInvalidCommitment,
    );
    assert!(
        group_ops::equal(
            &supply_new_commitment,
            &ristretto255::g_sub(&asset.privacy.confidential_supply_commitment, &amount_commitment),
        ),
        EInvalidCommitment,
    );
    verify_range(amount_commitment, amount_range_proof);
    verify_range(account_new_available, account_new_range_proof);
    verify_range(supply_new_commitment, supply_new_range_proof);

    account.confidential.available = account_new_available;
    asset.privacy.confidential_supply_commitment = supply_new_commitment;

    event::emit(ConfidentialBurnEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        amount_commitment,
    });
}

fun apply_pending_confidential_internal<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    new_available_bytes: vector<u8>,
    range_proof: vector<u8>,
    encrypted_available_for_owner: vector<u8>,
    encrypted_available_for_viewers: vector<vector<u8>>,
    enforce_not_frozen: bool,
) {
    // Pause halts movement, not confidential balance recovery. Applying pending
    // notes only folds already-credited pending state into available state.
    assert_privacy_enabled(asset);
    assert_account(asset, account);
    if (enforce_not_frozen) {
        assert_not_frozen(account);
    };
    assert_confidential_account_enabled(account);
    assert_opening_bytes(&encrypted_available_for_owner);
    assert_opening_bytes_vector(&encrypted_available_for_viewers);

    let new_available = commitment_from_bytes(new_available_bytes);
    assert!(
        group_ops::equal(
            &new_available,
            &ristretto255::g_add(&account.confidential.available, &account.confidential.pending),
        ),
        EInvalidCommitment,
    );
    verify_range(new_available, range_proof);

    account.confidential.available = new_available;
    account.confidential.pending = ristretto255::g_identity();
    clear_pending_confidential_notes(account);
    account.confidential.encrypted_available_for_owner = encrypted_available_for_owner;
    account.confidential.encrypted_available_for_viewers = encrypted_available_for_viewers;
}

fun prepare_transferable_debit<T>(
    account: &mut Account<T>,
    amount: u64,
    now_ms: &Option<u64>,
) {
    prune_unlocked_restricted_lots(account, now_ms);
    assert_transferable_balance(account, amount, now_ms);
}

fun set_confidential_pending_limit_internal<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    max_pending_notes: u64,
) {
    assert_account(asset, account);
    assert!(max_pending_notes <= MAX_PENDING_CONFIDENTIAL_NOTES, EMaxPendingConfidentialNotes);
    account.confidential.max_pending_notes = max_pending_notes;
    event::emit(ConfidentialPendingLimitUpdatedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        max_pending_notes,
    });
}

fun set_confidential_credits_enabled_internal<T>(
    asset: &Asset<T>,
    account: &mut Account<T>,
    enabled: bool,
) {
    assert_privacy_enabled(asset);
    assert_account(asset, account);
    account.allow_confidential_credits = enabled;
    event::emit(AccountFlagsUpdatedEvent {
        asset_id: object::id(asset),
        account_id: object::id(account),
        memo_required: account.memo_required,
        allow_public_credits: account.allow_public_credits,
        allow_confidential_credits: enabled,
    });
}

fun credit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    if (amount == 0) {
        return
    };
    if (account.balance == 0) {
        register_positive_account(asset, account.identity);
    };
    account.balance = checked_add(account.balance, amount);
}

fun debit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    if (amount == 0) {
        return
    };
    assert!(account.balance >= amount, EInsufficientBalance);
    account.balance = account.balance - amount;
    if (account.balance == 0) {
        account.locked_balance = 0;
        account.restricted_lots = vector[];
        unregister_positive_account(asset, account.identity);
    };
}

fun force_debit_account<T>(
    asset: &mut Asset<T>,
    account: &mut Account<T>,
    amount: u64,
) {
    if (amount == 0) {
        return
    };
    assert!(account.balance >= amount, EInsufficientBalance);
    account.balance = account.balance - amount;
    if (account.balance == 0) {
        account.locked_balance = 0;
        account.restricted_lots = vector[];
        unregister_positive_account(asset, account.identity);
    } else {
        cap_locks_to_balance(account);
    };
}

fun cap_locks_to_balance<T>(account: &mut Account<T>) {
    if (account.locked_balance > account.balance) {
        account.locked_balance = account.balance;
    };

    let mut remaining = account.balance;
    let mut kept = vector[];
    while (account.restricted_lots.length() > 0) {
        let mut lot = account.restricted_lots.pop_back();
        if (remaining > 0 && lot.amount > 0) {
            if (lot.amount > remaining) {
                lot.amount = remaining;
            };
            remaining = remaining - lot.amount;
            kept.push_back(lot);
        };
    };
    while (kept.length() > 0) {
        account.restricted_lots.push_back(kept.pop_back());
    };
}

fun push_pending_confidential_note<T>(
    account: &mut Account<T>,
    recipient_note: vector<u8>,
    viewer_notes: vector<vector<u8>>,
) {
    assert_pending_note_capacity(account);
    let index = account.confidential.pending_note_count;
    account.confidential.encrypted_pending_notes.add(index, PendingEncryptedNote {
        recipient_note,
        viewer_notes,
    });
    account.confidential.pending_note_count = index + 1;
}

fun clear_pending_confidential_notes<T>(account: &mut Account<T>) {
    let mut index = 0;
    while (index < account.confidential.pending_note_count) {
        let _note = account.confidential.encrypted_pending_notes.remove(index);
        index = index + 1;
    };
    account.confidential.pending_note_count = 0;
}

fun register_positive_account<T>(asset: &mut Asset<T>, identity: IdentityKey) {
    let mut identity_positive_accounts = 1;
    if (asset.shareholder_accounts.contains(identity)) {
        let count = asset.shareholder_accounts.borrow_mut(identity);
        *count = checked_add(*count, 1);
        identity_positive_accounts = *count;
    } else {
        let new_total = checked_add(asset.total_shareholders, 1);
        assert_shareholder_cap(new_total, asset.max_shareholders);
        asset.shareholder_accounts.add(identity, 1);
        asset.total_shareholders = new_total;
    };

    event::emit(ShareholderCountUpdatedEvent {
        asset_id: object::id(asset),
        identity,
        identity_positive_accounts,
        total_shareholders: asset.total_shareholders,
    });
}

fun unregister_positive_account<T>(asset: &mut Asset<T>, identity: IdentityKey) {
    if (!asset.shareholder_accounts.contains(identity)) {
        return
    };

    let identity_positive_accounts;
    let mut remove_holder = false;
    {
        let count = asset.shareholder_accounts.borrow_mut(identity);
        if (*count > 1) {
            *count = *count - 1;
            identity_positive_accounts = *count;
        } else {
            identity_positive_accounts = 0;
            remove_holder = true;
        };
    };

    if (remove_holder) {
        let _removed = asset.shareholder_accounts.remove(identity);
        asset.total_shareholders = asset.total_shareholders - 1;
    };

    event::emit(ShareholderCountUpdatedEvent {
        asset_id: object::id(asset),
        identity,
        identity_positive_accounts,
        total_shareholders: asset.total_shareholders,
    });
}

fun prune_unlocked_restricted_lots<T>(account: &mut Account<T>, now_ms: &Option<u64>) {
    if (now_ms.is_none()) {
        return
    };

    let now = *now_ms.borrow();
    let mut kept = vector[];
    while (account.restricted_lots.length() > 0) {
        let lot = account.restricted_lots.pop_back();
        if (lot.amount > 0 && lot.unlock_ms > now) {
            kept.push_back(lot);
        };
    };
    while (kept.length() > 0) {
        account.restricted_lots.push_back(kept.pop_back());
    };
}

fun compute_fee(fee: &FeeConfig, amount: u64): u64 {
    let value = ((amount as u128) * (fee.bps as u128) / (MAX_BPS as u128)) +
        (fee.fixed as u128);
    assert!(value <= (std::u64::max_value!() as u128), EInvalidFee);
    value as u64
}

fun checked_add(left: u64, right: u64): u64 {
    assert!(left <= std::u64::max_value!() - right, EAmountOverflow);
    left + right
}

fun available_transferable_balance<T>(account: &Account<T>, now_ms: &Option<u64>): u64 {
    let locked = checked_add(account.locked_balance, restricted_locked_balance_internal(account, now_ms));
    if (locked >= account.balance) {
        0
    } else {
        account.balance - locked
    }
}

fun restricted_locked_balance_internal<T>(account: &Account<T>, now_ms: &Option<u64>): u64 {
    let mut total = 0;
    let mut i = 0;
    let len = account.restricted_lots.length();
    while (i < len) {
        let lot = &account.restricted_lots[i];
        let locked = if (now_ms.is_some()) {
            lot.unlock_ms > *now_ms.borrow()
        } else {
            lot.amount > 0
        };
        if (locked) {
            total = checked_add(total, lot.amount);
        };
        i = i + 1;
    };
    total
}

fun scaled_u64(value: u64, numerator: u64, denominator: u64): u64 {
    assert_valid_display_scale(numerator, denominator);
    let scaled = (value as u128) * (numerator as u128) / (denominator as u128);
    assert!(scaled <= (std::u64::max_value!() as u128), EAmountOverflow);
    scaled as u64
}

fun assert_valid_display_scale(numerator: u64, denominator: u64) {
    assert!(numerator > 0 && denominator > 0, EInvalidDisplayScale);
}

fun commitment_from_bytes(bytes: vector<u8>): Element<ristretto255::G> {
    assert!(bytes.length() == RISTRETTO_POINT_BYTES, EInvalidCommitment);
    ristretto255::g_from_bytes(&bytes)
}

fun verify_range(commitment: Element<ristretto255::G>, proof: vector<u8>) {
    let commitments = vector[commitment];
    assert!(
        rangeproofs::verify_bulletproofs_ristretto255(
            &proof,
            RANGE_BITS_U64,
            &commitments,
            BULLETPROOFS_VERSION,
        ),
        EInvalidRangeProof,
    );
}

fun assert_valid_mode(mode: u8) {
    assert!(mode == MODE_ALLOWLIST || mode == MODE_DENYLIST || mode == MODE_OPEN, EInvalidMode);
}

fun assert_valid_holder(holder: HolderKey) {
    assert!(
        holder.kind == HOLDER_ADDRESS ||
            holder.kind == HOLDER_OBJECT ||
            holder.kind == HOLDER_PACKAGE,
        EInvalidHolderKind,
    );
}

fun assert_valid_identity(identity: IdentityKey) {
    assert!(
        identity.kind == IDENTITY_ADDRESS ||
            identity.kind == IDENTITY_OBJECT ||
            identity.kind == IDENTITY_EXTERNAL,
        EInvalidHolderKind,
    );
}

fun assert_valid_kyc_status(status: u8) {
    assert!(
        status == KYC_UNKNOWN ||
            status == KYC_APPROVED ||
            status == KYC_DENIED ||
            status == KYC_PENDING ||
            status == KYC_EXPIRED ||
            status == KYC_EXEMPT,
        EInvalidKycStatus,
    );
}

fun assert_own_address_account(holder: HolderKey, identity: IdentityKey, ctx: &TxContext) {
    assert!(holder.kind == HOLDER_ADDRESS, EInvalidHolderKind);
    assert!(holder.addr == ctx.sender(), ENotAuthorized);
    assert!(identity == identity_from_holder(holder), ENotAuthorized);
}

fun assert_vector_size(bytes: &vector<u8>, max: u64) {
    assert!(bytes.length() <= max, EInvalidVectorSize);
}

fun assert_external_ref_hash(bytes: &vector<u8>) {
    assert_vector_size(bytes, MAX_EXTERNAL_REF_HASH_BYTES);
}

fun assert_encrypted_note(bytes: &vector<u8>) {
    assert_vector_size(bytes, MAX_ENCRYPTED_NOTE_BYTES);
}

fun assert_encrypted_notes_for_viewers(notes: &vector<vector<u8>>) {
    assert!(notes.length() <= MAX_VIEWER_NOTES, EInvalidVectorSize);
    let mut i = 0;
    let len = notes.length();
    while (i < len) {
        assert_encrypted_note(&notes[i]);
        i = i + 1;
    };
}

fun assert_opening_bytes(bytes: &vector<u8>) {
    assert_vector_size(bytes, MAX_ENCRYPTED_NOTE_BYTES);
}

fun assert_opening_bytes_vector(openings: &vector<vector<u8>>) {
    assert!(openings.length() <= MAX_ENCRYPTED_OPENINGS, EInvalidVectorSize);
    let mut i = 0;
    let len = openings.length();
    while (i < len) {
        assert_opening_bytes(&openings[i]);
        i = i + 1;
    };
}

fun assert_account<T>(asset: &Asset<T>, account: &Account<T>) {
    assert!(account.asset_id == object::id(asset), EAssetMismatch);
}

fun assert_cap<T>(asset: &Asset<T>, cap_asset_id: ID) {
    assert!(cap_asset_id == object::id(asset), ECapAssetMismatch);
}

fun assert_not_frozen<T>(account: &Account<T>) {
    assert!(!account.frozen, EAccountFrozen);
}

fun assert_max_supply(max_supply: Option<u64>, supply: u64) {
    if (max_supply.is_some()) {
        assert!(supply <= *max_supply.borrow(), EMaxSupplyExceeded);
    };
}

fun assert_shareholder_cap(total_shareholders: u64, max_shareholders: Option<u64>) {
    if (max_shareholders.is_some()) {
        assert!(total_shareholders <= *max_shareholders.borrow(), EShareholderCapExceeded);
    };
}

fun assert_transferable_balance<T>(
    account: &Account<T>,
    amount: u64,
    now_ms: &Option<u64>,
) {
    assert!(available_transferable_balance(account, now_ms) >= amount, EInsufficientBalance);
}

fun assert_restricted_lot_capacity<T>(account: &Account<T>) {
    assert!(account.restricted_lots.length() < MAX_RESTRICTED_LOTS, ERestrictedLotLimit);
}

fun assert_not_paused<T>(asset: &Asset<T>) {
    assert!(!asset.paused, EPaused);
}

fun assert_transferable<T>(asset: &Asset<T>) {
    assert!(!asset.non_transferable, ENonTransferable);
}

fun assert_no_transfer_rules<T>(asset: &Asset<T>) {
    assert!(asset.transfer_rules.is_empty(), ETransferRulesRequired);
}

fun assert_transfer_rule_approvals<T>(
    asset: &Asset<T>,
    approvals: &VecSet<type_name::TypeName>,
) {
    let rules = asset.transfer_rules.keys();
    let rules_len = rules.length();
    let mut i = 0;
    while (i < rules_len) {
        assert!(approvals.contains(&rules[i]), ETransferRuleMissing);
        i = i + 1;
    };
}

fun set_witness_authorization<T, W: drop>(asset: &mut Asset<T>, status: u8) {
    let witness = type_name::with_original_ids<W>();
    if (asset.authorized_witnesses.contains(witness)) {
        if (*asset.authorized_witnesses.borrow(witness) == AUTH_PERMANENT) {
            assert!(status == AUTH_PERMANENT, EAuthorizationPermanent);
        } else {
            *asset.authorized_witnesses.borrow_mut(witness) = status;
        };
    } else {
        asset.authorized_witnesses.add(witness, status);
    };
}

fun set_package_authorization<T>(asset: &mut Asset<T>, package_addr: address, status: u8) {
    if (asset.authorized_packages.contains(package_addr)) {
        if (*asset.authorized_packages.borrow(package_addr) == AUTH_PERMANENT) {
            assert!(status == AUTH_PERMANENT, EAuthorizationPermanent);
        } else {
            *asset.authorized_packages.borrow_mut(package_addr) = status;
        };
    } else {
        asset.authorized_packages.add(package_addr, status);
    };
}

fun set_object_authorization<T>(asset: &mut Asset<T>, object_id: ID, status: u8) {
    if (asset.authorized_object_holders.contains(object_id)) {
        if (*asset.authorized_object_holders.borrow(object_id) == AUTH_PERMANENT) {
            assert!(status == AUTH_PERMANENT, EAuthorizationPermanent);
        } else {
            *asset.authorized_object_holders.borrow_mut(object_id) = status;
        };
    } else {
        asset.authorized_object_holders.add(object_id, status);
    };
}

fun authorization_active(status: u8): bool {
    status == AUTH_ACTIVE || status == AUTH_PERMANENT
}

fun assert_identity_allowed<T>(asset: &Asset<T>, identity: IdentityKey, now_ms: &Option<u64>) {
    let allowed = if (asset.mode == MODE_OPEN) {
        true
    } else if (asset.mode == MODE_ALLOWLIST) {
        if (!asset.kyc.contains(identity)) {
            false
        } else {
            let record = asset.kyc.borrow(identity);
            (record.status == KYC_APPROVED || record.status == KYC_EXEMPT) &&
                kyc_record_time_valid(record, now_ms)
        }
    } else {
        if (!asset.kyc.contains(identity)) {
            true
        } else {
            let record = asset.kyc.borrow(identity);
            record.status != KYC_DENIED &&
                record.status != KYC_EXPIRED &&
                kyc_record_time_valid(record, now_ms)
        }
    };
    assert!(allowed, EHolderNotAllowed);
}

fun kyc_record_time_valid(record: &KycRecord, now_ms: &Option<u64>): bool {
    if (record.expires_ms == 0) {
        true
    } else if (now_ms.is_some()) {
        *now_ms.borrow() <= record.expires_ms
    } else {
        // Expiring KYC fails closed unless callers use the matching *_with_clock path.
        false
    }
}

fun assert_public_credit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    assert!(account.allow_public_credits, EPublicCreditDisabled);
    assert_identity_allowed(asset, account.identity, now_ms);
}

fun assert_public_debit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    assert_identity_allowed(asset, account.identity, now_ms);
}

fun assert_confidential_credit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    assert_confidential_account_enabled(account);
    assert!(account.allow_confidential_credits, EConfidentialCreditDisabled);
    assert_identity_allowed(asset, account.identity, now_ms);
}

fun assert_confidential_debit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
) {
    assert_confidential_account_enabled(account);
    assert_identity_allowed(asset, account.identity, now_ms);
}

fun assert_confidential_account_enabled<T>(account: &Account<T>) {
    assert!(account.confidential.enabled, EConfidentialAccountDisabled);
}

fun assert_no_pending_confidential<T>(account: &Account<T>) {
    assert!(
        group_ops::equal(&account.confidential.pending, &ristretto255::g_identity()) &&
            account.confidential.pending_note_count == 0,
        EConfidentialPendingNotEmpty,
    );
}

fun assert_pending_note_capacity<T>(account: &Account<T>) {
    assert!(
        account.confidential.pending_note_count < account.confidential.max_pending_notes,
        EMaxPendingConfidentialNotes,
    );
}

fun assert_memo<T>(account: &Account<T>, memo: &vector<u8>) {
    assert_vector_size(memo, MAX_MEMO_BYTES);
    assert!(!account.memo_required || memo.length() > 0, EMemoRequired);
}

fun assert_privacy_enabled<T>(asset: &Asset<T>) {
    assert!(asset.privacy.enabled, EPrivacyDisabled);
}

fun assert_confidential_allowed_with_shareholder_caps<T>(asset: &Asset<T>) {
    assert!(
        asset.max_shareholders.is_none(),
        EConfidentialShareholderCapsUnsupported,
    );
}

fun assert_owner_authorized<T>(account: &Account<T>, ctx: &TxContext) {
    assert!(account.holder.kind == HOLDER_ADDRESS, ENotAuthorized);
    assert!(account.holder.addr == ctx.sender(), ENotAuthorized);
}

fun assert_object_authorized<T, Authority: key>(
    asset: &Asset<T>,
    authority: &Authority,
    account: &Account<T>,
) {
    // Possession of an object reference is only accepted after the issuer has
    // explicitly authorized that object ID for this asset. Shared authority
    // objects must still enforce their own access control before calling here.
    let authority_id = object::id(authority);
    assert!(account.holder.kind == HOLDER_OBJECT, ENotAuthorized);
    assert!(account.holder.addr == object::id_to_address(&authority_id), ENotAuthorized);
    assert!(
        asset.authorized_object_holders.contains(authority_id) &&
            authorization_active(*asset.authorized_object_holders.borrow(authority_id)),
        ENotAuthorized,
    );
}

fun assert_package_authorized<T, W: drop>(asset: &Asset<T>, account: &Account<T>) {
    let package_addr = type_name::original_id<W>();
    let witness = type_name::with_original_ids<W>();
    assert!(account.holder.kind == HOLDER_PACKAGE, ENotAuthorized);
    assert!(account.holder.addr == package_addr, ENotAuthorized);
    let package_authorized = asset.authorized_packages.contains(package_addr) &&
        authorization_active(*asset.authorized_packages.borrow(package_addr));
    let witness_authorized = asset.authorized_witnesses.contains(witness) &&
        authorization_active(*asset.authorized_witnesses.borrow(witness));
    assert!(package_authorized || witness_authorized, ENotAuthorized);
}
