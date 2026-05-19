#[test_only]
module regulated_account::metadata_tests;

use regulated_account::asset;
use regulated_account::metadata;
use regulated_account::test_helpers;
use std::unit_test::{assert_eq, destroy};
use sui::test_scenario as ts;

public struct TEST has drop {}

#[test]
fun metadata_cap_updates_metadata() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let (mut metadata, metadata_cap) = test_helpers::new_metadata(&asset, ctx);

        metadata::set(
            &mut metadata,
            &metadata_cap,
            b"NRT".to_string(),
            b"New Regulated Account".to_string(),
            b"New description".to_string(),
            b"https://example.com/new.png".to_string(),
        );

        assert_eq!(metadata::asset_id(&metadata), asset::id(&asset));
        assert_eq!(metadata::symbol(&metadata), b"NRT".to_string());
        assert_eq!(metadata::name(&metadata), b"New Regulated Account".to_string());
        assert_eq!(metadata::description(&metadata), b"New description".to_string());
        assert_eq!(metadata::icon_url(&metadata), b"https://example.com/new.png".to_string());
        assert_eq!(metadata::decimals(&metadata), 9);

        destroy(asset);
        destroy(metadata);
        destroy(metadata_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun metadata_cap_updates_decimals() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let (mut metadata, metadata_cap) = test_helpers::new_metadata(&asset, ctx);

        assert_eq!(metadata::decimals(&metadata), 9);
        metadata::set_decimals(&mut metadata, &metadata_cap, 6);
        assert_eq!(metadata::decimals(&metadata), 6);

        destroy(asset);
        destroy(metadata);
        destroy(metadata_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun metadata_registry_indexes_by_receipt_type() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let mut registry = test_helpers::new_metadata_registry(ctx);
        let (
            asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let (metadata, metadata_cap) = test_helpers::new_metadata(&asset, ctx);

        assert!(!metadata::registered<TEST>(&registry), 0);
        metadata::register(&mut registry, &metadata, &metadata_cap);
        assert!(metadata::registered<TEST>(&registry), 1);
        metadata::assert_registered<TEST>(&registry, &metadata);

        let registered_id = metadata::registered_id<TEST>(&registry);
        assert!(registered_id.is_some(), 2);
        assert_eq!(*registered_id.borrow(), metadata::id(&metadata));

        let removed_id = test_helpers::remove_registered_metadata<TEST>(&mut registry);
        assert_eq!(removed_id, metadata::id(&metadata));
        test_helpers::destroy_metadata_registry(registry);

        destroy(asset);
        destroy(metadata);
        destroy(metadata_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 27, location = regulated_account::validation)]
fun metadata_symbol_length_is_bounded() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let (mut metadata, metadata_cap) = test_helpers::new_metadata(&asset, ctx);

        metadata::set(
            &mut metadata,
            &metadata_cap,
            b"SYMBOL_TOO_LONG_SYMBOL_TOO_LONG_SYMBOL_TOO_LONG_1".to_string(),
            b"Name".to_string(),
            b"Description".to_string(),
            b"https://example.com/icon.png".to_string(),
        );

        destroy(asset);
        destroy(metadata);
        destroy(metadata_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}
