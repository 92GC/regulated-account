module regulated_account::receipt;

public struct Receipt<phantom T> has key, store {
    id: UID,
    asset_id: ID,
    account_id: ID,
}

public(package) fun new<T>(
    asset_id: ID,
    account_id: ID,
    ctx: &mut TxContext,
): Receipt<T> {
    Receipt { id: object::new(ctx), asset_id, account_id }
}

public fun destroy<T>(receipt: Receipt<T>) {
    let Receipt { id, .. } = receipt;
    id.delete();
}

public fun account_id<T>(receipt: &Receipt<T>): ID {
    receipt.account_id
}

public fun asset_id<T>(receipt: &Receipt<T>): ID {
    receipt.asset_id
}
