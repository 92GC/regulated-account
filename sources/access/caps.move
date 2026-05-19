module regulated_account::caps;

const ECapAssetMismatch: u64 = 4;

public struct MintCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct FreezeCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct BurnCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct ClawbackCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct PolicyCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct RegistrationCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct CloseMintCap<phantom T> has key, store { id: UID, asset_id: ID }
public struct MetadataCap<phantom MetadataType> has key, store { id: UID, metadata_id: ID }
public struct PauseCap<phantom T> has key, store { id: UID, asset_id: ID }

public(package) fun new_mint<T>(asset_id: ID, ctx: &mut TxContext): MintCap<T> {
    MintCap { id: object::new(ctx), asset_id }
}

public(package) fun new_freeze<T>(asset_id: ID, ctx: &mut TxContext): FreezeCap<T> {
    FreezeCap { id: object::new(ctx), asset_id }
}

public(package) fun new_burn<T>(asset_id: ID, ctx: &mut TxContext): BurnCap<T> {
    BurnCap { id: object::new(ctx), asset_id }
}

public(package) fun new_clawback<T>(asset_id: ID, ctx: &mut TxContext): ClawbackCap<T> {
    ClawbackCap { id: object::new(ctx), asset_id }
}

public(package) fun new_policy<T>(asset_id: ID, ctx: &mut TxContext): PolicyCap<T> {
    PolicyCap { id: object::new(ctx), asset_id }
}

public(package) fun new_registration<T>(asset_id: ID, ctx: &mut TxContext): RegistrationCap<T> {
    RegistrationCap { id: object::new(ctx), asset_id }
}

public(package) fun new_close_mint<T>(asset_id: ID, ctx: &mut TxContext): CloseMintCap<T> {
    CloseMintCap { id: object::new(ctx), asset_id }
}

public(package) fun new_metadata<MetadataType>(
    metadata_id: ID,
    ctx: &mut TxContext,
): MetadataCap<MetadataType> {
    MetadataCap { id: object::new(ctx), metadata_id }
}

public(package) fun new_pause<T>(asset_id: ID, ctx: &mut TxContext): PauseCap<T> {
    PauseCap { id: object::new(ctx), asset_id }
}

public(package) fun assert_mint<T>(asset_id: ID, cap: &MintCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_freeze<T>(asset_id: ID, cap: &FreezeCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_burn<T>(asset_id: ID, cap: &BurnCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_clawback<T>(asset_id: ID, cap: &ClawbackCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_policy<T>(asset_id: ID, cap: &PolicyCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_registration<T>(asset_id: ID, cap: &RegistrationCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_close_mint<T>(asset_id: ID, cap: &CloseMintCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun assert_pause<T>(asset_id: ID, cap: &PauseCap<T>) {
    assert!(cap.asset_id == asset_id, ECapAssetMismatch);
}

public(package) fun metadata_id<MetadataType>(cap: &MetadataCap<MetadataType>): ID {
    cap.metadata_id
}
