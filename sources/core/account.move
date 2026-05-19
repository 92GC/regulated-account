module regulated_account::account;

use regulated_account::amount_math;
use regulated_account::authority::{Self, Time};
use regulated_account::keys::{Self, HolderKey, IdentityKey};
use regulated_account::restricted_lots::{Self, RestrictedLot, RestrictedLots};
use regulated_account::validation;

const EAssetMismatch: u64 = 3;
const EAccountFrozen: u64 = 6;
const EInsufficientBalance: u64 = 8;
const EImmutableHolder: u64 = 14;
const ELockedBalanceExceeded: u64 = 24;
const ENotAuthorized: u64 = 5;
const ETimeRequired: u64 = 33;

/// Shared per-holder balance account for one regulated asset type.
public struct Account<phantom T> has key {
    id: UID,
    asset_id: ID,
    holder: HolderKey,
    identity: IdentityKey,
    balance: u64,
    locked_balance: u64,
    restricted_lots: RestrictedLots,
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
    if (keys::is_holder_address(holder)) {
        assert!(identity == keys::identity_from_holder(holder), ENotAuthorized);
    };
    Account {
        id: object::new(ctx),
        asset_id,
        holder,
        identity,
        balance: 0,
        locked_balance: 0,
        restricted_lots: restricted_lots::empty(),
        frozen,
        immutable_holder,
        memo_required,
        allow_public_credits,
    }
}

public(package) fun share<T>(account: Account<T>) {
    transfer::share_object(account);
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
public fun restricted_lot_count<T>(account: &Account<T>): u64 {
    restricted_lots::count(&account.restricted_lots)
}

public fun restricted_lots<T>(account: &Account<T>): vector<RestrictedLot> {
    restricted_lots::lots(&account.restricted_lots)
}

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
    if (keys::is_holder_address(holder)) {
        assert!(account.identity == keys::identity_from_holder(holder), ENotAuthorized);
    };
    account.holder = holder;
}

public(package) fun set_identity<T>(account: &mut Account<T>, identity: IdentityKey): IdentityKey {
    keys::assert_valid_identity(identity);
    if (keys::is_holder_address(account.holder)) {
        assert!(identity == keys::identity_from_holder(account.holder), ENotAuthorized);
    };
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
        account.restricted_lots = restricted_lots::empty();
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
    if (!restricted_lots::is_empty(&account.restricted_lots)) {
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
    restricted_lots::add(&mut account.restricted_lots, amount, unlock_ms, external_ref_hash);
}

public(package) fun restricted_locked_balance<T>(account: &Account<T>, now_ms: &Option<u64>): u64 {
    restricted_lots::locked_balance(&account.restricted_lots, now_ms)
}

public(package) fun transferable_balance<T>(account: &Account<T>, now_ms: &Option<u64>): u64 {
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
    restricted_lots::prune_unlocked(&mut account.restricted_lots, now_ms);
}

fun cap_locks_to_balance<T>(account: &mut Account<T>) {
    if (account.locked_balance > account.balance) {
        account.locked_balance = account.balance;
    };
    restricted_lots::cap_to_balance(&mut account.restricted_lots, account.balance);
}
