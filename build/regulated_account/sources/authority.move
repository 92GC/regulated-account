module regulated_account::authority;

use std::type_name;
use sui::clock::{Self, Clock};

const AUTHORITY_OWNER: u8 = 0;
const AUTHORITY_PACKAGE: u8 = 1;

/// Hot-potato proof that a holder authorized a transfer from one of its accounts.
public struct HolderAuthority<phantom T> {
    kind: u8,
    addr: address,
    witness: Option<type_name::TypeName>,
}

/// Optional timestamp evidence for compliance and lock checks.
public struct Time {
    now_ms: Option<u64>,
}

/// Creates time evidence with no clock.
/// Time-sensitive checks fail closed: expiring KYC is not considered current, and
/// restricted lots are treated as locked.
public fun no_time(): Time {
    Time { now_ms: option::none() }
}

/// Creates time evidence from the Sui clock for KYC expiry and restricted-lot checks.
public fun clock_time(clock: &Clock): Time {
    Time { now_ms: option::some(clock::timestamp_ms(clock)) }
}

/// Authorizes an address-held account when `ctx.sender()` matches the account holder.
public fun owner_authority<T>(ctx: &TxContext): HolderAuthority<T> {
    HolderAuthority {
        kind: AUTHORITY_OWNER,
        addr: ctx.sender(),
        witness: option::none(),
    }
}

/// Authorizes a package-held account for the package that defines witness `W`.
public fun package_authority<T, W: drop>(_witness: W): HolderAuthority<T> {
    HolderAuthority {
        kind: AUTHORITY_PACKAGE,
        addr: type_name::original_id<W>(),
        witness: option::some(type_name::with_original_ids<W>()),
    }
}

public(package) fun is_owner(kind: u8): bool {
    kind == AUTHORITY_OWNER
}

public(package) fun is_package(kind: u8): bool {
    kind == AUTHORITY_PACKAGE
}

public(package) fun time_to_option(time: Time): Option<u64> {
    let Time { now_ms } = time;
    now_ms
}

public(package) fun unpack<T>(
    authority: HolderAuthority<T>,
): (u8, address, Option<type_name::TypeName>) {
    let HolderAuthority { kind, addr, witness } = authority;
    (kind, addr, witness)
}
