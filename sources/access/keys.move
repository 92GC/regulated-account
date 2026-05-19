module regulated_account::keys;

use regulated_account::constants;

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
    HolderKey { kind: constants::holder_address_kind(), addr }
}

public fun holder_package(package_addr: address): HolderKey {
    HolderKey { kind: constants::holder_package_kind(), addr: package_addr }
}

public fun identity_address(addr: address): IdentityKey {
    IdentityKey { kind: constants::identity_address_kind(), addr }
}

public fun identity_external(addr: address): IdentityKey {
    IdentityKey { kind: constants::identity_external_kind(), addr }
}

public fun identity_from_holder(holder: HolderKey): IdentityKey {
    let kind = if (holder.kind == constants::holder_address_kind()) {
        constants::identity_address_kind()
    } else if (holder.kind == constants::holder_package_kind()) {
        constants::identity_external_kind()
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

public fun identity_addr(identity: IdentityKey): address {
    identity.addr
}

public fun is_holder_address(holder: HolderKey): bool {
    holder.kind == constants::holder_address_kind()
}

public fun is_holder_package(holder: HolderKey): bool {
    holder.kind == constants::holder_package_kind()
}

public fun is_identity_address(identity: IdentityKey): bool {
    identity.kind == constants::identity_address_kind()
}

public fun is_identity_external(identity: IdentityKey): bool {
    identity.kind == constants::identity_external_kind()
}

public(package) fun assert_valid_holder(holder: HolderKey) {
    assert!(
        holder.kind == constants::holder_address_kind() ||
            holder.kind == constants::holder_package_kind(),
        EInvalidHolderKind,
    );
}

public(package) fun assert_valid_identity(identity: IdentityKey) {
    assert!(
        identity.kind == constants::identity_address_kind() ||
            identity.kind == constants::identity_external_kind(),
        EInvalidIdentityKind,
    );
}
