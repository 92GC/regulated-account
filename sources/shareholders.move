module regulated_account::shareholders;

use regulated_account::amount_math;
use regulated_account::policy_events;
use regulated_account::keys::IdentityKey;
use sui::table::{Self, Table};

const EShareholderCapExceeded: u64 = 23;
const EMinPositiveBalance: u64 = 31;
const EMinPositiveBalanceMigrationRequired: u64 = 34;

/// Bounded positive-balance account counts by legal identity.
public struct Shareholders has store {
    total: u64,
    max: Option<u64>,
    min_positive_balance: u64,
    accounts: Table<IdentityKey, u64>,
}

public(package) fun new(ctx: &mut TxContext): Shareholders {
    Shareholders {
        total: 0,
        max: option::none(),
        min_positive_balance: 0,
        accounts: table::new(ctx),
    }
}

public fun total(shareholders: &Shareholders): u64 { shareholders.total }
public fun cap(shareholders: &Shareholders): Option<u64> { shareholders.max }
public fun min_positive_balance(shareholders: &Shareholders): u64 {
    shareholders.min_positive_balance
}

public fun identity_positive_account_count(
    shareholders: &Shareholders,
    identity: IdentityKey,
): u64 {
    if (shareholders.accounts.contains(identity)) {
        *shareholders.accounts.borrow(identity)
    } else {
        0
    }
}

public(package) fun set_cap(shareholders: &mut Shareholders, max: Option<u64>) {
    assert_cap(shareholders.total, max);
    shareholders.max = max;
}

public(package) fun set_min_positive_balance(shareholders: &mut Shareholders, min_balance: u64) {
    assert!(
        min_balance <= shareholders.min_positive_balance || shareholders.total == 0,
        EMinPositiveBalanceMigrationRequired
    );
    shareholders.min_positive_balance = min_balance;
}

public(package) fun register(asset_id: ID, shareholders: &mut Shareholders, identity: IdentityKey) {
    let mut identity_positive_accounts = 1;
    if (shareholders.accounts.contains(identity)) {
        let count = shareholders.accounts.borrow_mut(identity);
        *count = amount_math::checked_add(*count, 1);
        identity_positive_accounts = *count;
    } else {
        let new_total = amount_math::checked_add(shareholders.total, 1);
        assert_cap(new_total, shareholders.max);
        shareholders.accounts.add(identity, 1);
        shareholders.total = new_total;
    };
    policy_events::emit_shareholder_count_updated(
        asset_id,
        identity,
        identity_positive_accounts,
        shareholders.total,
    );
}

public(package) fun unregister(
    asset_id: ID,
    shareholders: &mut Shareholders,
    identity: IdentityKey,
) {
    if (!shareholders.accounts.contains(identity)) {
        return
    };

    let identity_positive_accounts;
    let mut remove_holder = false;
    {
        let count = shareholders.accounts.borrow_mut(identity);
        if (*count > 1) {
            *count = *count - 1;
            identity_positive_accounts = *count;
        } else {
            identity_positive_accounts = 0;
            remove_holder = true;
        };
    };

    if (remove_holder) {
        let _removed = shareholders.accounts.remove(identity);
        shareholders.total = shareholders.total - 1;
    };

    policy_events::emit_shareholder_count_updated(
        asset_id,
        identity,
        identity_positive_accounts,
        shareholders.total,
    );
}

public(package) fun transfer_identity(
    asset_id: ID,
    shareholders: &mut Shareholders,
    previous_identity: IdentityKey,
    identity: IdentityKey,
) {
    if (shareholders.accounts.contains(identity)) {
        unregister(asset_id, shareholders, previous_identity);
        register(asset_id, shareholders, identity);
        return
    };

    let previous_count = *shareholders.accounts.borrow(previous_identity);
    if (previous_count == 1) {
        let _removed = shareholders.accounts.remove(previous_identity);
        shareholders.accounts.add(identity, 1);

        policy_events::emit_shareholder_count_updated(asset_id, previous_identity, 0, shareholders.total);
        policy_events::emit_shareholder_count_updated(asset_id, identity, 1, shareholders.total);
        return
    };

    let previous_identity_positive_accounts = previous_count - 1;
    *shareholders.accounts.borrow_mut(previous_identity) = previous_identity_positive_accounts;

    let new_total = amount_math::checked_add(shareholders.total, 1);
    assert_cap(new_total, shareholders.max);
    shareholders.accounts.add(identity, 1);
    shareholders.total = new_total;

    policy_events::emit_shareholder_count_updated(
        asset_id,
        previous_identity,
        previous_identity_positive_accounts,
        shareholders.total,
    );
    policy_events::emit_shareholder_count_updated(asset_id, identity, 1, shareholders.total);
}

public(package) fun assert_min_positive_balance(shareholders: &Shareholders, balance: u64) {
    assert!(balance == 0 || balance >= shareholders.min_positive_balance, EMinPositiveBalance);
}

fun assert_cap(total: u64, max: Option<u64>) {
    if (max.is_some()) {
        assert!(total <= *max.borrow(), EShareholderCapExceeded);
    };
}
