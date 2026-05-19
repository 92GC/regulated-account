module regulated_account::authority;

use std::type_name;
use regulated_account::constants;
use sui::clock::{Self, Clock};
use sui::table::{Self, Table};

/// Hot-potato proof that a holder authorized a transfer from one of its accounts.
public struct HolderAuthority<phantom T> {
    kind: u8,
    addr: address,
    witness: Option<type_name::TypeName>,
}

/// Optional timestamp evidence for KYC and proof-expiry checks.
public struct Time {
    now_ms: Option<u64>,
}

/// Authorized package witnesses for package-held account control.
public struct WitnessPolicy has store {
    witnesses: Table<type_name::TypeName, bool>,
}

/// Creates time evidence with no clock.
/// Time-sensitive checks fail closed: expiring KYC is not considered current.
public fun no_time(): Time {
    Time { now_ms: option::none() }
}

/// Creates time evidence from the Sui clock for KYC and proof-expiry checks.
public fun clock_time(clock: &Clock): Time {
    Time { now_ms: option::some(clock::timestamp_ms(clock)) }
}

/// Authorizes an address-held account when `ctx.sender()` matches the account holder.
public fun owner_authority<T>(ctx: &TxContext): HolderAuthority<T> {
    HolderAuthority {
        kind: constants::authority_owner(),
        addr: ctx.sender(),
        witness: option::none(),
    }
}

/// Authorizes a package-held account for the package that defines witness `W`.
public fun package_authority<T, W: drop>(_witness: W): HolderAuthority<T> {
    HolderAuthority {
        kind: constants::authority_package(),
        addr: type_name::original_id<W>(),
        witness: option::some(type_name::with_original_ids<W>()),
    }
}

public(package) fun is_owner(kind: u8): bool {
    kind == constants::authority_owner()
}

public(package) fun is_package(kind: u8): bool {
    kind == constants::authority_package()
}

public(package) fun time_to_option(time: Time): Option<u64> {
    let Time { now_ms } = time;
    now_ms
}

public(package) fun new_witness_policy(ctx: &mut TxContext): WitnessPolicy {
    WitnessPolicy { witnesses: table::new(ctx) }
}

public(package) fun authorized_witness<W: drop>(policy: &WitnessPolicy): bool {
    witness_authorized(policy, type_name::with_original_ids<W>())
}

public(package) fun authorize_witness<W: drop>(
    policy: &mut WitnessPolicy,
): type_name::TypeName {
    let witness = type_name::with_original_ids<W>();
    if (policy.witnesses.contains(witness)) {
        *policy.witnesses.borrow_mut(witness) = true;
    } else {
        policy.witnesses.add(witness, true);
    };
    witness
}

public(package) fun deauthorize_witness<W: drop>(
    policy: &mut WitnessPolicy,
): type_name::TypeName {
    let witness = type_name::with_original_ids<W>();
    if (policy.witnesses.contains(witness)) {
        let _removed = policy.witnesses.remove(witness);
    };
    witness
}

public(package) fun witness_authorized(
    policy: &WitnessPolicy,
    witness: type_name::TypeName,
): bool {
    policy.witnesses.contains(witness) &&
        *policy.witnesses.borrow(witness)
}

public(package) fun unpack<T>(
    authority: HolderAuthority<T>,
): (u8, address, Option<type_name::TypeName>) {
    let HolderAuthority { kind, addr, witness } = authority;
    (kind, addr, witness)
}
