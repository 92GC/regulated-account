module regulated_account::restricted_lots;

use regulated_account::amount_math;
use regulated_account::constants;

const ERestrictedLotLimit: u64 = 25;

/// Time-locked balance lot. The amount is non-transferable until `unlock_ms`.
public struct RestrictedLot has copy, drop, store {
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
}

public struct RestrictedLots has copy, drop, store {
    lots: vector<RestrictedLot>,
    total_amount: u64,
}

public(package) fun empty(): RestrictedLots {
    RestrictedLots { lots: vector[], total_amount: 0 }
}

public(package) fun is_empty(restricted_lots: &RestrictedLots): bool {
    restricted_lots.lots.is_empty()
}

public(package) fun count(restricted_lots: &RestrictedLots): u64 {
    restricted_lots.lots.length()
}

public(package) fun lots(restricted_lots: &RestrictedLots): vector<RestrictedLot> {
    restricted_lots.lots
}

public fun amount(lot: &RestrictedLot): u64 {
    lot.amount
}

public fun unlock_ms(lot: &RestrictedLot): u64 {
    lot.unlock_ms
}

public fun external_ref_hash(lot: &RestrictedLot): vector<u8> {
    lot.external_ref_hash
}

public(package) fun add(
    restricted_lots: &mut RestrictedLots,
    amount: u64,
    unlock_ms: u64,
    external_ref_hash: vector<u8>,
) {
    if (amount == 0) {
        return
    };

    let (found, index) = find_lot_index(restricted_lots, unlock_ms, &external_ref_hash);
    restricted_lots.total_amount = amount_math::checked_add(restricted_lots.total_amount, amount);

    if (found) {
        let lot = &mut restricted_lots.lots[index];
        lot.amount = amount_math::checked_add(lot.amount, amount);
    } else {
        assert!(
            restricted_lots.lots.length() < constants::max_restricted_lots(),
            ERestrictedLotLimit,
        );
        let lot = RestrictedLot { amount, unlock_ms, external_ref_hash };
        restricted_lots.lots.insert(lot, index);
    };
}

public(package) fun locked_balance(restricted_lots: &RestrictedLots, now_ms: &Option<u64>): u64 {
    if (now_ms.is_none()) {
        return restricted_lots.total_amount
    };

    let now = *now_ms.borrow();
    if (!has_unlocked_at(restricted_lots, now)) {
        return restricted_lots.total_amount
    };

    let mut unlocked = 0;
    let mut i = 0;
    let len = restricted_lots.lots.length();
    while (i < len) {
        let lot = &restricted_lots.lots[i];
        if (lot.unlock_ms > now) {
            break
        };
        unlocked = amount_math::checked_add(unlocked, lot.amount);
        i = i + 1;
    };
    restricted_lots.total_amount - unlocked
}

public(package) fun prune_unlocked(
    restricted_lots: &mut RestrictedLots,
    now_ms: &Option<u64>,
) {
    if (now_ms.is_none()) {
        return
    };

    let now = *now_ms.borrow();
    if (!has_unlocked_at(restricted_lots, now)) {
        return
    };

    let mut kept = vector[];
    let mut total_amount = 0;
    let mut i = 0;
    let len = restricted_lots.lots.length();
    while (i < len) {
        let lot = restricted_lots.lots[i];
        if (lot.amount > 0 && lot.unlock_ms > now) {
            total_amount = amount_math::checked_add(total_amount, lot.amount);
            kept.push_back(lot);
        };
        i = i + 1;
    };
    restricted_lots.lots = kept;
    restricted_lots.total_amount = total_amount;
}

public(package) fun cap_to_balance(restricted_lots: &mut RestrictedLots, balance: u64) {
    // Restricted lots are stored by ascending unlock time, so force debits preserve
    // the earliest-unlocking lots and trim later-unlocking lots first.
    let mut remaining = balance;
    let mut kept = vector[];
    let mut total_amount = 0;
    let mut i = 0;
    let len = restricted_lots.lots.length();
    while (i < len) {
        let mut lot = restricted_lots.lots[i];
        if (remaining > 0 && lot.amount > 0) {
            if (lot.amount > remaining) {
                lot.amount = remaining;
            };
            remaining = remaining - lot.amount;
            total_amount = amount_math::checked_add(total_amount, lot.amount);
            kept.push_back(lot);
        };
        i = i + 1;
    };
    restricted_lots.lots = kept;
    restricted_lots.total_amount = total_amount;
}

fun find_lot_index(
    restricted_lots: &RestrictedLots,
    unlock_ms: u64,
    external_ref_hash: &vector<u8>,
): (bool, u64) {
    let mut low = 0;
    let mut high = restricted_lots.lots.length();
    while (low < high) {
        let mid = low + ((high - low) / 2);
        let lot = &restricted_lots.lots[mid];
        if (lot_key_less(lot, unlock_ms, external_ref_hash)) {
            low = mid + 1;
        } else {
            high = mid;
        };
    };

    if (low < restricted_lots.lots.length()) {
        let lot = &restricted_lots.lots[low];
        if (lot.unlock_ms == unlock_ms && &lot.external_ref_hash == external_ref_hash) {
            return (true, low)
        };
    };
    (false, low)
}

fun lot_key_less(lot: &RestrictedLot, unlock_ms: u64, external_ref_hash: &vector<u8>): bool {
    lot.unlock_ms < unlock_ms ||
        (lot.unlock_ms == unlock_ms && ref_hash_less(&lot.external_ref_hash, external_ref_hash))
}

fun ref_hash_less(left: &vector<u8>, right: &vector<u8>): bool {
    let mut i = 0;
    let left_len = left.length();
    let right_len = right.length();
    while (i < left_len && i < right_len) {
        let left_byte = *left.borrow(i);
        let right_byte = *right.borrow(i);
        if (left_byte < right_byte) {
            return true
        };
        if (left_byte > right_byte) {
            return false
        };
        i = i + 1;
    };
    left_len < right_len
}

fun has_unlocked_at(restricted_lots: &RestrictedLots, now: u64): bool {
    !restricted_lots.lots.is_empty() && restricted_lots.lots[0].unlock_ms <= now
}
