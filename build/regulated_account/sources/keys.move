module regulated_account::keys;

const HOLDER_ADDRESS: u8 = 0;
const HOLDER_PACKAGE: u8 = 1;

const IDENTITY_ADDRESS: u8 = 0;
const IDENTITY_EXTERNAL: u8 = 1;

const EInvalidHolderKind: u64 = 3;
const EInvalidIdentityKind: u64 = 4;

public struct HolderKey has copy, drop, store {
    kind: u8,
    addr: address,
}

public struct IdentityKey has copy, drop, store {
    kind: u8,
    addr: address,
}

public fun holder_address(addr: address): HolderKey {
    HolderKey { kind: HOLDER_ADDRESS, addr }
}

public fun holder_package(package_addr: address): HolderKey {
    HolderKey { kind: HOLDER_PACKAGE, addr: package_addr }
}

public fun identity_address(addr: address): IdentityKey {
    IdentityKey { kind: IDENTITY_ADDRESS, addr }
}

public fun identity_external(addr: address): IdentityKey {
    IdentityKey { kind: IDENTITY_EXTERNAL, addr }
}

public fun identity_from_holder(holder: HolderKey): IdentityKey {
    let kind = if (holder.kind == HOLDER_ADDRESS) {
        IDENTITY_ADDRESS
    } else if (holder.kind == HOLDER_PACKAGE) {
        IDENTITY_EXTERNAL
    } else {
        abort EInvalidHolderKind
    };
    IdentityKey { kind, addr: holder.addr }
}

public fun holder_addr(holder: HolderKey): address {
    holder.addr
}

public fun holder_kind(holder: HolderKey): u8 {
    holder.kind
}

public fun identity_kind(identity: IdentityKey): u8 {
    identity.kind
}

public fun is_holder_address(holder: HolderKey): bool {
    holder.kind == HOLDER_ADDRESS
}

public fun is_holder_package(holder: HolderKey): bool {
    holder.kind == HOLDER_PACKAGE
}

public fun assert_valid_holder(holder: HolderKey) {
    assert!(
        holder.kind == HOLDER_ADDRESS ||
            holder.kind == HOLDER_PACKAGE,
        EInvalidHolderKind,
    );
}

public fun assert_valid_identity(identity: IdentityKey) {
    assert!(
        identity.kind == IDENTITY_ADDRESS ||
            identity.kind == IDENTITY_EXTERNAL,
        EInvalidIdentityKind,
    );
}
