#[test_only]
module regulated_account::regulated_account_tests;

use regulated_account::account;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::compliance;
use regulated_account::keys;
use regulated_account::ledger;
use regulated_account::metadata;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::type_name;
use std::unit_test::{assert_eq, destroy};
use sui::clock;
use sui::test_scenario as ts;

public struct TEST has drop {}
public struct WrapperWitness has drop {}
public struct TypedTerms<phantom T> has key {
    id: UID,
    asset_id: ID,
    account_id: ID,
}

#[test]
fun public_mint_transfer_and_burn() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 1_000);
        assert_eq!(account::balance(&alice), 1_000);
        assert_eq!(asset::supply(&asset), 1_000);

        transfer_ops::transfer(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, &mut bob, 250, vector[]);
        assert_eq!(account::balance(&alice), 750);
        assert_eq!(account::balance(&bob), 250);

        ledger::admin_burn(&mut asset, &burn_cap, &mut bob, 50, b"admin-burn");
        assert_eq!(account::balance(&bob), 200);
        assert_eq!(asset::supply(&asset), 950);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

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
            fee_cap,
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
        destroy(fee_cap);
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
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let (metadata, metadata_cap) = test_helpers::new_metadata(&asset, ctx);

        assert!(!metadata::registered<TEST>(&registry), 0);
        metadata::register(&mut registry, &metadata);
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
        destroy(fee_cap);
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
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let (mut metadata, metadata_cap) = test_helpers::new_metadata(&asset, ctx);

        metadata::set(
            &mut metadata,
            &metadata_cap,
            b"SYMBOL_TOO_LONG_1".to_string(),
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
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun allowlist_requires_kyc() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            identity,
            asset::kyc_approved(),
            0,
            b"kyc-ref",
        );
        assert!(asset::has_kyc(&asset, identity), 0);
        assert_eq!(asset::kyc_status(&asset, identity), asset::kyc_approved());
        assert_eq!(asset::kyc_expires_ms(&asset, identity), 0);
        assert_eq!(asset::kyc_external_ref_hash(&asset, identity), b"kyc-ref");

        let account = test_helpers::new_account(&asset, holder, true, ctx);
        assert_eq!(account::balance(&account), 0);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 26, location = regulated_account::kyc)]
fun invalid_kyc_status_is_rejected() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_address(ctx.sender()),
            99,
            0,
            b"bad-status",
        );

        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 7, location = regulated_account::asset)]
fun denylisted_sender_cannot_transfer_out() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::denylist_mode(), ctx);

        let alice_holder = keys::holder_address(ctx.sender());
        let mut alice = test_helpers::new_account(&asset, alice_holder, true, ctx);
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 100);
        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(alice_holder),
            asset::kyc_denied(),
            0,
            b"blocked",
        );
        transfer_ops::transfer(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, &mut bob, 1, vector[]);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 11, location = regulated_account::asset)]
fun locked_compliance_mode_blocks_mode_changes() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        compliance::lock_compliance_mode(&mut asset, &policy_cap, b"lock-mode");
        compliance::set_compliance_mode(&mut asset, &policy_cap, asset::denylist_mode(), b"change-mode");

        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 9, location = regulated_account::fees)]
fun zero_fee_config_uses_clear_fee_config() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(&mut asset, &fee_cap, authority::no_time(), 0, 0, &fees, b"fee");

        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 9, location = regulated_account::fees)]
fun fee_config_rejects_full_bps_plus_fixed_fee() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(&mut asset, &fee_cap, authority::no_time(), 10_000, 1, &fees, b"fee");

        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 13, location = regulated_account::compliance)]
fun fee_config_requires_receiver_that_can_accept_public_credits() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            false,
            ctx,
        );

        compliance::set_fee_config(&mut asset, &fee_cap, authority::no_time(), 0, 1, &fees, b"fee");

        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun freeze_and_thaw_account() {
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
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        compliance::freeze_account(&asset, &freeze_cap, &mut account, b"freeze");
        assert!(account::frozen(&account), 0);
        compliance::thaw(&asset, &freeze_cap, &mut account, b"thaw");
        assert!(!account::frozen(&account), 1);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun display_scale_changes_display_units_without_rewriting_balance() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut account, 100);
        assert_eq!(account::balance(&account), 100);
        let display_balance = account::display_balance(&asset, &account);
        let display_supply = asset::display_supply(&asset);
        assert!(display_balance.is_some());
        assert_eq!(*display_balance.borrow(), 100);
        assert!(display_supply.is_some());
        assert_eq!(*display_supply.borrow(), 100);

        asset::set_display_scale(&mut asset, &policy_cap, 2, 1);
        let (num, den) = asset::display_scale(&asset);
        assert_eq!(num, 2);
        assert_eq!(den, 1);
        assert_eq!(account::balance(&account), 100);
        let scaled_balance = account::display_balance(&asset, &account);
        let scaled_supply = asset::display_supply(&asset);
        assert!(scaled_balance.is_some());
        assert_eq!(*scaled_balance.borrow(), 200);
        assert!(scaled_supply.is_some());
        assert_eq!(*scaled_supply.borrow(), 200);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 22, location = regulated_account::asset)]
fun max_supply_blocks_mint_above_authorized_amount() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        asset::set_max_supply(&mut asset, &mint_cap, option::some(100), b"max-supply");
        let max_supply = asset::max_supply(&asset);
        assert!(max_supply.is_some(), 0);
        assert_eq!(*max_supply.borrow(), 100);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut account, 101);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 25, location = regulated_account::amount_math)]
fun display_scale_rejects_overflowing_current_supply() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut account, std::u64::max_value!());
        asset::set_display_scale(&mut asset, &policy_cap, 2, 1);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun display_views_return_none_on_overflow() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            &mut account,
            std::u64::max_value!() / 2 + 1,
        );

        assert!(account::display_balance(&asset, &account).is_some(), 0);
        test_helpers::set_display_scale(&mut asset, 2, 1);
        assert!(account::display_balance(&asset, &account).is_none(), 1);
        assert!(asset::display_supply(&asset).is_none(), 2);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 23, location = regulated_account::shareholders)]
fun shareholder_cap_blocks_new_holder() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        compliance::set_shareholder_caps(&mut asset, &policy_cap, option::some(1), b"holder-cap");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 10);
        assert_eq!(asset::total_shareholders(&asset), 1);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut bob, 10);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun shareholder_cap_counts_identity_not_wallets() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let identity = keys::identity_address(@0x1D);
        let mut wallet_a = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_address(ctx.sender()),
            identity,
            true,
            ctx,
        );
        let mut wallet_b = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_address(@0xB0B),
            identity,
            true,
            ctx,
        );

        compliance::set_shareholder_caps(&mut asset, &policy_cap, option::some(1), b"holder-cap");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut wallet_a, 10);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut wallet_b, 20);

        assert_eq!(asset::total_shareholders(&asset), 1);
        assert_eq!(asset::identity_positive_account_count(&asset, identity), 2);

        destroy(wallet_a);
        destroy(wallet_b);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun set_identity_reuses_shareholder_slot_when_old_identity_exits() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let registration_cap = test_helpers::new_registration_cap(&asset, ctx);

        let old_identity = keys::identity_address(ctx.sender());
        let new_identity = keys::identity_address(@0xC0FFEE);
        let mut account = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_address(ctx.sender()),
            old_identity,
            true,
            ctx,
        );

        compliance::set_shareholder_caps(&mut asset, &policy_cap, option::some(1), b"holder-cap");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut account, 100);
        compliance::set_identity(
            &mut asset,
            &registration_cap,
            authority::no_time(),
            &mut account,
            new_identity,
            b"identity-fix",
        );

        assert_eq!(asset::total_shareholders(&asset), 1);
        assert_eq!(asset::identity_positive_account_count(&asset, old_identity), 0);
        assert_eq!(asset::identity_positive_account_count(&asset, new_identity), 1);
        assert_eq!(account::identity(&account), new_identity);

        destroy(account);
        destroy(asset);
        destroy(registration_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 31, location = regulated_account::shareholders)]
fun min_positive_balance_blocks_dust_mint() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        assert_eq!(asset::min_positive_balance(&asset), 100);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut account, 99);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 31, location = regulated_account::shareholders)]
fun min_positive_balance_blocks_dust_remainder() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 150);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut bob, 100);
        transfer_ops::transfer(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, &mut bob, 60, vector[]);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun min_positive_balance_allows_full_exit() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 150);
        transfer_ops::transfer(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, &mut bob, 150, vector[]);

        assert_eq!(account::balance(&alice), 0);
        assert_eq!(account::balance(&bob), 150);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 31, location = regulated_account::shareholders)]
fun min_positive_balance_blocks_fee_transfer_dust_remainder() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            0,
            10,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 150);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut bob, 100);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut fees, 100);
        transfer_ops::transfer_with_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut bob,
            &mut fees,
            60,
            vector[],
        );

        destroy(alice);
        destroy(bob);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun min_positive_balance_does_not_block_fee_receiver_credit() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 10, b"min-balance");
        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            0,
            5,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 100);
        transfer_ops::transfer_with_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut bob,
            &mut fees,
            20,
            vector[],
        );

        assert_eq!(account::balance(&alice), 80);
        assert_eq!(account::balance(&bob), 15);
        assert_eq!(account::balance(&fees), 5);

        destroy(alice);
        destroy(bob);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 31, location = regulated_account::shareholders)]
fun min_positive_balance_blocks_recipient_fee_receiver_dust_credit() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            10_000,
            0,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 200);
        transfer_ops::transfer_with_recipient_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut fees,
            5,
            vector[],
        );

        destroy(alice);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun package_witness_authorizes_wrapper_account_unwrap() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let wrapper_addr = type_name::original_id<WrapperWitness>();
        let mut wrapper_account = test_helpers::new_account(
            &asset,
            keys::holder_package(wrapper_addr),
            true,
            ctx,
        );
        let mut user_account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        compliance::authorize_witness<TEST, WrapperWitness>(&mut asset, &policy_cap);
        assert!(asset::authorized_witness<TEST, WrapperWitness>(&asset), 0);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut wrapper_account, 500);

        transfer_ops::transfer(
            &mut asset,
            authority::package_authority<TEST, WrapperWitness>(WrapperWitness {}),
            authority::no_time(),
            &mut wrapper_account,
            &mut user_account,
            125,
            vector[],
        );

        assert_eq!(account::balance(&wrapper_account), 375);
        assert_eq!(account::balance(&user_account), 125);

        destroy(wrapper_account);
        destroy(user_account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun allowlist_wrapper_deposit_and_unwrap_flow() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let user_holder = keys::holder_address(ctx.sender());
        let user_identity = keys::identity_from_holder(user_holder);
        let wrapper_addr = type_name::original_id<WrapperWitness>();
        let wrapper_identity = keys::identity_external(@0xCAFE);

        compliance::set_kyc(&mut asset, &policy_cap, user_identity, asset::kyc_approved(), 0, b"user-kyc");
        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            wrapper_identity,
            asset::kyc_approved(),
            0,
            b"wrapper-kyc",
        );

        let mut user_account = test_helpers::new_account_with_identity(
            &asset,
            user_holder,
            user_identity,
            true,
            ctx,
        );
        let mut wrapper_account = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_package(wrapper_addr),
            wrapper_identity,
            true,
            ctx,
        );

        compliance::authorize_witness<TEST, WrapperWitness>(&mut asset, &policy_cap);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut user_account, 500);

        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut user_account,
            &mut wrapper_account,
            200,
            vector[],
        );
        assert_eq!(account::balance(&user_account), 300);
        assert_eq!(account::balance(&wrapper_account), 200);

        transfer_ops::transfer(
            &mut asset,
            authority::package_authority<TEST, WrapperWitness>(WrapperWitness {}),
            authority::no_time(),
            &mut wrapper_account,
            &mut user_account,
            125,
            vector[],
        );
        assert_eq!(account::balance(&user_account), 425);
        assert_eq!(account::balance(&wrapper_account), 75);

        destroy(user_account);
        destroy(wrapper_account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 5, location = regulated_account::compliance)]
fun package_witness_must_be_authorized_for_wrapper_outbound_transfer() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let wrapper_addr = type_name::original_id<WrapperWitness>();
        let mut wrapper_account = test_helpers::new_account(
            &asset,
            keys::holder_package(wrapper_addr),
            true,
            ctx,
        );
        let mut user_account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut wrapper_account, 500);
        transfer_ops::transfer(
            &mut asset,
            authority::package_authority<TEST, WrapperWitness>(WrapperWitness {}),
            authority::no_time(),
            &mut wrapper_account,
            &mut user_account,
            125,
            vector[],
        );

        destroy(wrapper_account);
        destroy(user_account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 5, location = regulated_account::compliance)]
fun package_witness_must_match_wrapper_holder_package() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut wrapper_account = test_helpers::new_account(
            &asset,
            keys::holder_package(@0xBAD),
            true,
            ctx,
        );
        let mut user_account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        compliance::authorize_witness<TEST, WrapperWitness>(&mut asset, &policy_cap);
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut wrapper_account, 500);
        transfer_ops::transfer(
            &mut asset,
            authority::package_authority<TEST, WrapperWitness>(WrapperWitness {}),
            authority::no_time(),
            &mut wrapper_account,
            &mut user_account,
            125,
            vector[],
        );

        destroy(wrapper_account);
        destroy(user_account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 8, location = regulated_account::account)]
fun locked_balance_blocks_partial_transfer() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 100);
        compliance::set_locked_balance(&asset, &freeze_cap, &mut alice, 80, b"lock");
        assert_eq!(account::transferable_balance_at(&alice, authority::no_time()), 20);
        transfer_ops::transfer(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, &mut bob, 25, vector[]);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun transferable_balance_saturates_when_locks_overlap() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let max = std::u64::max_value!();
        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut account, max, 10_000, b"grant");
        compliance::set_locked_balance(&asset, &freeze_cap, &mut account, max, b"lock");

        assert_eq!(account::transferable_balance_at(&account, authority::no_time()), 0);

        destroy(account);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun clawback_reaches_locked_and_restricted_balance() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 100, 10_000, b"grant");
        compliance::set_locked_balance(&asset, &freeze_cap, &mut alice, 100, b"lock");
        ledger::clawback(&mut asset, &clawback_cap, &mut alice, &mut bob, 100, b"clawback");

        assert_eq!(account::balance(&alice), 0);
        assert_eq!(account::balance(&bob), 100);
        assert_eq!(account::locked_balance(&alice), 0);
        assert_eq!(account::restricted_lot_count(&alice), 0);

        destroy(alice);
        destroy(bob);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun clawback_bypasses_recipient_kyc_for_admin_recovery() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::denylist_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let treasury_holder = keys::holder_address(@0xFEE);
        let mut treasury = test_helpers::new_account(
            &asset,
            treasury_holder,
            true,
            ctx,
        );
        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(treasury_holder),
            asset::kyc_denied(),
            0,
            b"treasury-denied",
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 100);
        ledger::clawback(&mut asset, &clawback_cap, &mut alice, &mut treasury, 25, b"clawback");

        assert_eq!(account::balance(&alice), 75);
        assert_eq!(account::balance(&treasury), 25);

        destroy(alice);
        destroy(treasury);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun clawback_bypasses_min_positive_balance_for_admin_recovery() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut recovery = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 200);
        ledger::clawback(&mut asset, &clawback_cap, &mut alice, &mut recovery, 5, b"clawback");

        assert_eq!(account::balance(&alice), 195);
        assert_eq!(account::balance(&recovery), 5);

        destroy(alice);
        destroy(recovery);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun partial_clawback_caps_locked_and_restricted_lots() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 90);
        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 50, 20_000, b"grant-b");
        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 60, 10_000, b"grant-a");
        compliance::set_locked_balance(&asset, &freeze_cap, &mut alice, 80, b"lock");

        ledger::clawback(&mut asset, &clawback_cap, &mut alice, &mut bob, 70, b"clawback");

        assert_eq!(account::balance(&alice), 130);
        assert_eq!(account::locked_balance(&alice), 80);
        assert_eq!(account::restricted_locked_balance_at(&alice, authority::no_time()), 50);
        assert_eq!(account::transferable_balance_at(&alice, authority::no_time()), 0);
        clock::set_for_testing(&mut clock, 15_000);
        assert_eq!(account::restricted_locked_balance_at(&alice, authority::clock_time(&clock)), 0);
        assert_eq!(account::balance(&bob), 70);

        destroy(alice);
        destroy(bob);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun restricted_lot_unlocks_with_explicit_time() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 100, 1_000, b"rule-144");
        assert_eq!(account::restricted_lot_count(&alice), 1);
        assert_eq!(account::transferable_balance_at(&alice, authority::no_time()), 0);
        clock::set_for_testing(&mut clock, 1_000);
        assert_eq!(account::transferable_balance_at(&alice, authority::clock_time(&clock)), 100);

        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::clock_time(&clock),
            &mut alice,
            &mut bob,
            60,
            vector[],
        );
        assert_eq!(account::balance(&alice), 40);
        assert_eq!(account::balance(&bob), 60);
        assert_eq!(account::restricted_lot_count(&alice), 0);

        destroy(alice);
        destroy(bob);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 32, location = regulated_account::ledger)]
fun restricted_mint_without_clock_fails() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            &mut alice,
            100,
            1_000,
            b"no-clock",
        );

        destroy(alice);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 32, location = regulated_account::ledger)]
fun restricted_mint_with_clock_rejects_already_unlocked_lot() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 1_000);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            100,
            1_000,
            b"already-unlocked",
        );

        destroy(alice);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun restricted_mint_with_clock_prunes_expired_lots_before_capacity_check() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        let mut i: u64 = 0;
        while (i < 128) {
            let mut external_ref_hash = vector[];
            external_ref_hash.push_back((i as u8));
            ledger::mint_restricted(
                &mut asset,
                &mint_cap,
                authority::clock_time(&clock),
                &mut alice,
                1,
                1,
                external_ref_hash,
            );
            i = i + 1;
        };
        assert_eq!(account::restricted_lot_count(&alice), 128);

        clock::set_for_testing(&mut clock, 10);
        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            1,
            20,
            b"new-grant",
        );

        assert_eq!(account::restricted_lot_count(&alice), 1);
        assert_eq!(account::restricted_locked_balance_at(&alice, authority::clock_time(&clock)), 1);

        destroy(alice);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun matching_restricted_lots_are_coalesced() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 40, 10_000, b"same-grant");
        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 60, 10_000, b"same-grant");

        assert_eq!(account::restricted_lot_count(&alice), 1);
        assert_eq!(account::restricted_locked_balance_at(&alice, authority::no_time()), 100);

        destroy(alice);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun default_account_state_creates_frozen_accounts() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        compliance::set_default_account_frozen(&mut asset, &policy_cap, true, b"default-frozen");
        assert!(asset::default_account_frozen(&asset), 0);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        assert!(account::frozen(&account), 1);

        compliance::thaw(&asset, &freeze_cap, &mut account, b"thaw");
        assert!(!account::frozen(&account), 2);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}
#[test]
fun typed_extension_objects_can_bind_to_asset_and_account() {
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
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let terms = TypedTerms<TEST> {
            id: object::new(ctx),
            asset_id: asset::id(&asset),
            account_id: account::id(&account),
        };

        assert_eq!(terms.asset_id, asset::id(&asset));
        assert_eq!(terms.account_id, account::id(&account));

        let TypedTerms { id, .. } = terms;
        id.delete();
        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}
#[test, expected_failure(abort_code = 18, location = regulated_account::asset)]
fun pause_cap_blocks_transfers() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 100);
        compliance::pause(&mut asset, &pause_cap, b"pause");
        assert!(asset::paused(&asset), 0);
        transfer_ops::transfer(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, &mut bob, 1, vector[]);

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(pause_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 18, location = regulated_account::asset)]
fun pause_cap_blocks_mint() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        compliance::pause(&mut asset, &pause_cap, b"pause");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 1);

        destroy(alice);
        destroy(asset);
        destroy(pause_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 18, location = regulated_account::asset)]
fun pause_cap_blocks_public_burn() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 10);
        compliance::pause(&mut asset, &pause_cap, b"pause");
        ledger::burn(&mut asset, authority::owner_authority<TEST>(ctx), authority::no_time(), &mut alice, 1);

        destroy(alice);
        destroy(asset);
        destroy(pause_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun transfer_fees_credit_fee_account() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            1_000,
            5,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 1_000);
        transfer_ops::transfer_with_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut bob,
            &mut fees,
            100,
            vector[],
        );

        assert_eq!(account::balance(&alice), 900);
        assert_eq!(account::balance(&bob), 85);
        assert_eq!(account::balance(&fees), 15);

        destroy(alice);
        destroy(bob);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun configured_fee_receiver_can_send_with_sender_fee_path() {
    let mut scenario = ts::begin(@0xFEE);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            1_000,
            5,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut fees, 1_000);
        transfer_ops::transfer_with_sender_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut fees,
            &mut bob,
            100,
            vector[],
        );

        assert_eq!(account::balance(&fees), 915);
        assert_eq!(account::balance(&bob), 85);

        destroy(fees);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun configured_fee_receiver_can_receive_with_recipient_fee_path() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            1_000,
            5,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 1_000);
        transfer_ops::transfer_with_recipient_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut fees,
            100,
            vector[],
        );

        assert_eq!(account::balance(&alice), 900);
        assert_eq!(account::balance(&fees), 100);

        destroy(alice);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 28, location = regulated_account::fees)]
fun percent_fee_too_small_uses_specific_error() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            1,
            0,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 1);
        transfer_ops::transfer_with_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut bob,
            &mut fees,
            1,
            vector[],
        );

        destroy(alice);
        destroy(bob);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun bps_only_fee_config_allows_plain_zero_fee_dust_transfer() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );
        let fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            1,
            0,
            &fees,
            b"fee",
        );
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 1);
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut bob,
            1,
            vector[],
        );

        assert_eq!(account::balance(&alice), 0);
        assert_eq!(account::balance(&bob), 1);

        destroy(alice);
        destroy(bob);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 8, location = regulated_account::account)]
fun sender_fee_path_requires_gross_balance_even_when_net_zero() {
    let mut scenario = ts::begin(@0xFEE);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            10_000,
            0,
            &fees,
            b"fee",
        );
        transfer_ops::transfer_with_sender_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut fees,
            &mut bob,
            10,
            vector[],
        );

        destroy(fees);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 33, location = regulated_account::validation)]
fun zero_amount_mint_rejected() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, 0);

        destroy(alice);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = regulated_account::account)]
fun mint_to_frozen_account_fails() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        compliance::freeze_account(&asset, &freeze_cap, &mut account, b"freeze");
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut account, 1);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 7, location = regulated_account::asset)]
fun expiring_kyc_requires_clock_on_no_clock_paths() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let holder = keys::holder_address(ctx.sender());
        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(holder),
            asset::kyc_approved(),
            100,
            b"kyc",
        );
        let account = test_helpers::new_account(&asset, holder, true, ctx);

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun expiring_kyc_works_with_explicit_time_before_expiry() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 50);

        let holder = keys::holder_address(ctx.sender());
        compliance::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(holder),
            asset::kyc_approved(),
            100,
            b"kyc",
        );
        let account = test_helpers::new_account_at_time(
            &asset,
            holder,
            true,
            authority::clock_time(&clock),
            ctx,
        );

        assert_eq!(account::balance(&account), 0);

        destroy(account);
        clock::destroy_for_testing(clock);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun transfer_fee_uses_u128_math() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            fee_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut bob = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xB0B),
            true,
            ctx,
        );
        let mut fees = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        compliance::set_fee_config(
            &mut asset,
            &fee_cap,
            authority::no_time(),
            10_000,
            0,
            &fees,
            b"fee",
        );
        let max = std::u64::max_value!();
        ledger::mint(&mut asset, &mint_cap, authority::no_time(), &mut alice, max);
        transfer_ops::transfer_with_fee_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            &mut alice,
            &mut bob,
            &mut fees,
            max,
            vector[],
        );

        assert_eq!(account::balance(&alice), 0);
        assert_eq!(account::balance(&bob), 0);
        assert_eq!(account::balance(&fees), max);

        destroy(alice);
        destroy(bob);
        destroy(fees);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(fee_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}
