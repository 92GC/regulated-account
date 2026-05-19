module regulated_account::account;

use regulated_account::amount_math;
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, Time};
use regulated_account::caps::{Self, RegistrationCap};
use regulated_account::events;
use regulated_account::keys::{Self, HolderKey, IdentityKey};
use regulated_account::receipt;
use regulated_account::validation;

// A hard cap keeps restricted-lot scans bounded and predictable. Lots with the same
// unlock time and external reference hash are coalesced before this limit is checked.
const MAX_RESTRICTED_LOTS: u64 = 128;

const EAssetMismatch: u64 = 3;
const EAccountFrozen: u64 = 6;
const EInsufficientBalance: u64 = 8;
const EImmutableHolder: u64 = 14;
const ELockedBalanceExceeded: u64 = 24;
const ERestrictedLotLimit: u64 = 25;
const ENotAuthorized: u64 = 5;
const ETimeRequired: u64 = 33;

/// Time-locked balance lot. The amount is non-transferable until `unlock_ms`.
public struct RestrictedLot has copy, drop, store {
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
}

/// Shared per-holder balance account for one regulated asset type.
public struct Account<phantom T> has key {
    id: UID,
    asset_id: ID,
    holder: HolderKey,
    identity: IdentityKey,
    balance: u64,
    locked_balance: u64,
    restricted_lots: vector<RestrictedLot>,
    frozen: bool,
    immutable_holder: bool,
    memo_required: bool,
    allow_public_credits: bool,
}

public(package) fun new<T>(
    asset_id: ID,
    holder: HolderKey,
    identity: IdentityKey,
    frozen: bool,
    immutable_holder: bool,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
): Account<T> {
    keys::assert_valid_holder(holder);
    keys::assert_valid_identity(identity);
    Account {
        id: object::new(ctx),
        asset_id,
        holder,
        identity,
        balance: 0,
        locked_balance: 0,
        restricted_lots: vector[],
        frozen,
        immutable_holder,
        memo_required,
        allow_public_credits,
    }
}

public(package) fun share<T>(account: Account<T>) {
    transfer::share_object(account);
}

public fun create<T>(
    asset: &Asset<T>,
    time: Time,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
) {
    asset::assert_not_paused(asset);
    assert_own_address_account(holder, identity, ctx);
    create_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        false,
        memo_required,
        allow_public_credits,
        authority::time_to_option(time),
        ctx,
    )
}

public fun admin_create<T>(
    asset: &Asset<T>,
    cap: &RegistrationCap<T>,
    time: Time,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_holder: bool,
    memo_required: bool,
    allow_public_credits: bool,
    ctx: &mut TxContext,
) {
    caps::assert_registration(asset::id(asset), cap);
    create_internal(
        asset,
        holder,
        identity,
        receipt_recipient,
        immutable_holder,
        memo_required,
        allow_public_credits,
        authority::time_to_option(time),
        ctx,
    )
}

public fun id<T>(account: &Account<T>): ID { object::id(account) }
public fun asset_id<T>(account: &Account<T>): ID { account.asset_id }
public fun holder<T>(account: &Account<T>): HolderKey { account.holder }
public fun identity<T>(account: &Account<T>): IdentityKey { account.identity }
public fun balance<T>(account: &Account<T>): u64 { account.balance }
public fun locked_balance<T>(account: &Account<T>): u64 { account.locked_balance }
public fun frozen<T>(account: &Account<T>): bool { account.frozen }
public fun allow_public_credits<T>(account: &Account<T>): bool { account.allow_public_credits }
public fun memo_required<T>(account: &Account<T>): bool { account.memo_required }
public fun restricted_lot_count<T>(account: &Account<T>): u64 { account.restricted_lots.length() }
public fun restricted_lots<T>(account: &Account<T>): vector<RestrictedLot> { account.restricted_lots }

/// Returns the locked amount from restricted lots at `time`.
/// Passing `authority::no_time()` fails closed and treats every non-zero restricted lot as locked.
public fun restricted_locked_balance_at<T>(account: &Account<T>, time: Time): u64 {
    let now_ms = authority::time_to_option(time);
    restricted_locked_balance(account, &now_ms)
}

/// Returns spendable balance after static locks and restricted lots at `time`.
/// Passing `authority::no_time()` treats every non-zero restricted lot as locked.
public fun transferable_balance_at<T>(account: &Account<T>, time: Time): u64 {
    let now_ms = authority::time_to_option(time);
    transferable_balance(account, &now_ms)
}

public fun display_balance<T>(asset: &Asset<T>, account: &Account<T>): Option<u64> {
    assert_asset(account, asset::id(asset));
    asset::checked_display_balance(asset, balance(account))
}

public(package) fun assert_asset<T>(account: &Account<T>, asset_id: ID) {
    assert!(account.asset_id == asset_id, EAssetMismatch);
}

public(package) fun assert_own_address_account(
    holder: HolderKey,
    identity: IdentityKey,
    ctx: &TxContext,
) {
    assert!(keys::is_holder_address(holder), ENotAuthorized);
    assert!(keys::holder_addr(holder) == ctx.sender(), ENotAuthorized);
    assert!(identity == keys::identity_from_holder(holder), ENotAuthorized);
}

public(package) fun assert_not_frozen<T>(account: &Account<T>) {
    assert!(!account.frozen, EAccountFrozen);
}

public(package) fun assert_memo<T>(account: &Account<T>, memo: &vector<u8>) {
    validation::assert_memo_required(account.memo_required, memo);
}

public(package) fun set_frozen<T>(account: &mut Account<T>, frozen: bool) {
    account.frozen = frozen;
}

public(package) fun set_locked_balance<T>(account: &mut Account<T>, locked_balance: u64) {
    assert!(locked_balance <= account.balance, ELockedBalanceExceeded);
    account.locked_balance = locked_balance;
}

public(package) fun set_flags<T>(
    account: &mut Account<T>,
    memo_required: bool,
    allow_public_credits: bool,
) {
    account.memo_required = memo_required;
    account.allow_public_credits = allow_public_credits;
}

public(package) fun lock_holder<T>(account: &mut Account<T>) {
    account.immutable_holder = true;
}

public(package) fun set_holder<T>(account: &mut Account<T>, holder: HolderKey) {
    assert!(!account.immutable_holder, EImmutableHolder);
    keys::assert_valid_holder(holder);
    account.holder = holder;
}

public(package) fun set_identity<T>(account: &mut Account<T>, identity: IdentityKey): IdentityKey {
    keys::assert_valid_identity(identity);
    let previous = account.identity;
    account.identity = identity;
    previous
}

public(package) fun credit<T>(account: &mut Account<T>, amount: u64): bool {
    if (amount == 0) {
        return false
    };
    let was_zero = account.balance == 0;
    account.balance = amount_math::checked_add(account.balance, amount);
    was_zero
}

public(package) fun debit<T>(account: &mut Account<T>, amount: u64): bool {
    if (amount == 0) {
        return false
    };
    assert!(account.balance >= amount, EInsufficientBalance);
    account.balance = account.balance - amount;
    if (account.balance == 0) {
        account.locked_balance = 0;
        account.restricted_lots = vector[];
        true
    } else {
        false
    }
}

public(package) fun force_debit<T>(
    account: &mut Account<T>,
    amount: u64,
    now_ms: &Option<u64>,
): bool {
    if (account.restricted_lots.length() > 0) {
        assert!(now_ms.is_some(), ETimeRequired);
        prune_unlocked_restricted_lots(account, now_ms);
    };

    let became_zero = debit(account, amount);
    if (!became_zero) {
        cap_locks_to_balance(account);
    };
    became_zero
}

public(package) fun prepare_transferable_debit<T>(
    account: &mut Account<T>,
    amount: u64,
    now_ms: &Option<u64>,
) {
    prune_unlocked_restricted_lots(account, now_ms);
    assert!(transferable_balance(account, now_ms) >= amount, EInsufficientBalance);
}

public(package) fun add_restricted_lot<T>(
    account: &mut Account<T>,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
) {
    if (amount == 0) {
        return
    };

    let mut i = 0;
    let len = account.restricted_lots.length();
    while (i < len) {
        let lot = &mut account.restricted_lots[i];
        if (lot.unlock_ms == unlock_ms && &lot.external_ref_hash == &external_ref_hash) {
            lot.amount = amount_math::checked_add(lot.amount, amount);
            return
        };
        i = i + 1;
    };

    assert!(account.restricted_lots.length() < MAX_RESTRICTED_LOTS, ERestrictedLotLimit);
    let lot = RestrictedLot { amount, unlock_ms, external_ref_hash };
    let mut insert_at = account.restricted_lots.length();
    let mut j = 0;
    while (j < len) {
        if (unlock_ms < account.restricted_lots[j].unlock_ms) {
            insert_at = j;
            break
        };
        j = j + 1;
    };
    account.restricted_lots.insert(lot, insert_at);
}

public fun restricted_locked_balance<T>(account: &Account<T>, now_ms: &Option<u64>): u64 {
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
            total = amount_math::checked_add(total, lot.amount);
        };
        i = i + 1;
    };
    total
}

public fun transferable_balance<T>(account: &Account<T>, now_ms: &Option<u64>): u64 {
    if (account.locked_balance >= account.balance) {
        0
    } else {
        let remaining_after_lock = account.balance - account.locked_balance;
        let restricted = restricted_locked_balance(account, now_ms);
        if (restricted >= remaining_after_lock) {
            0
        } else {
            remaining_after_lock - restricted
        }
    }
}

public(package) fun prune_unlocked_restricted_lots<T>(
    account: &mut Account<T>,
    now_ms: &Option<u64>,
) {
    if (now_ms.is_none()) {
        return
    };

    let now = *now_ms.borrow();
    let mut kept = vector[];
    let mut i = 0;
    let len = account.restricted_lots.length();
    while (i < len) {
        let lot = account.restricted_lots[i];
        if (lot.amount > 0 && lot.unlock_ms > now) {
            kept.push_back(lot);
        };
        i = i + 1;
    };
    account.restricted_lots = kept;
}

fun cap_locks_to_balance<T>(account: &mut Account<T>) {
    if (account.locked_balance > account.balance) {
        account.locked_balance = account.balance;
    };

    // Restricted lots are stored by ascending unlock time, so force debits preserve
    // the earliest-unlocking lots and trim later-unlocking lots first.
    let mut remaining = account.balance;
    let mut kept = vector[];
    let mut i = 0;
    let len = account.restricted_lots.length();
    while (i < len) {
        let mut lot = account.restricted_lots[i];
        if (remaining > 0 && lot.amount > 0) {
            if (lot.amount > remaining) {
                lot.amount = remaining;
            };
            remaining = remaining - lot.amount;
            kept.push_back(lot);
        };
        i = i + 1;
    };
    account.restricted_lots = kept;
}

fun create_internal<T>(
    asset: &Asset<T>,
    holder: HolderKey,
    identity: IdentityKey,
    receipt_recipient: Option<address>,
    immutable_holder: bool,
    memo_required: bool,
    allow_public_credits: bool,
    now_ms: Option<u64>,
    ctx: &mut TxContext,
) {
    keys::assert_valid_holder(holder);
    keys::assert_valid_identity(identity);
    asset::assert_identity_allowed(asset, identity, &now_ms);
    let account: Account<T> = new(
        asset::id(asset),
        holder,
        identity,
        asset::default_account_frozen(asset),
        immutable_holder,
        memo_required,
        allow_public_credits,
        ctx,
    );
    let account_id = id(&account);
    let receipt_id = if (receipt_recipient.is_some()) {
        let receipt = receipt::new<T>(asset::id(asset), account_id, ctx);
        let id = object::id(&receipt);
        transfer::public_transfer(receipt, *receipt_recipient.borrow());
        option::some(id)
    } else {
        option::none()
    };

    events::emit_account_created(asset::id(asset), account_id, holder, identity, receipt_id);
    share(account);
}
