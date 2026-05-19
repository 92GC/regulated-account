#[test_only]
module regulated_account::regulated_account_tests;

use regulated_account::regulated_account as rt;
use std::type_name;
use std::unit_test;
use sui::clock;
use sui::group_ops;
use sui::ristretto255;
use sui::test_scenario as ts;

public struct TEST has drop {}
public struct Authority has key { id: UID }
public struct ProgramWitness has drop {}
public struct OtherWitness has drop {}
public struct ExternalRule has drop {}

fun new_authority(ctx: &mut TxContext): Authority {
    Authority { id: object::new(ctx) }
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut alice, 1_000);
        assert!(rt::balance(&alice) == 1_000, 0);
        assert!(rt::supply(&asset) == 1_000, 1);

        rt::transfer(&mut asset, &mut alice, &mut bob, 250, vector[], ctx);
        assert!(rt::balance(&alice) == 750, 2);
        assert!(rt::balance(&bob) == 250, 3);

        rt::admin_burn(&mut asset, &burn_cap, &mut bob, 50);
        assert!(rt::balance(&bob) == 200, 4);
        assert!(rt::supply(&asset) == 950, 5);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun metadata_cap_updates_metadata() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);
        let metadata_cap = rt::new_metadata_cap_for_testing(&asset, ctx);

        rt::set_metadata(
            &mut asset,
            &metadata_cap,
            b"NRT".to_string(),
            b"New Regulated Account".to_string(),
            b"New description".to_string(),
            b"https://example.com/new.png".to_string(),
        );

        assert!(rt::symbol(&asset) == b"NRT".to_string(), 0);
        assert!(rt::name(&asset) == b"New Regulated Account".to_string(), 1);
        assert!(rt::description(&asset) == b"New description".to_string(), 2);
        assert!(rt::icon_url(&asset) == b"https://example.com/new.png".to_string(), 3);
        assert!(rt::decimals(&asset) == 9, 4);

        unit_test::destroy(asset);
        unit_test::destroy(metadata_cap);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::allowlist_mode(), true, ctx);

        let holder = rt::holder_address(ctx.sender());
        rt::set_kyc(
            &mut asset,
            &policy_cap,
            rt::identity_from_holder(holder),
            rt::kyc_approved(),
            0,
            b"kyc-ref",
        );

        let account = rt::new_account_for_testing(&asset, holder, true, true, ctx);
        assert!(rt::balance(&account) == 0, 0);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 41, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        rt::set_kyc(
            &mut asset,
            &policy_cap,
            rt::identity_address(ctx.sender()),
            99,
            0,
            b"bad-status",
        );

        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 8, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::denylist_mode(), false, ctx);

        let alice_holder = rt::holder_address(ctx.sender());
        let mut alice = rt::new_account_for_testing(&asset, alice_holder, true, true, ctx);
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut alice, 100);
        rt::set_kyc(
            &mut asset,
            &policy_cap,
            rt::identity_from_holder(alice_holder),
            rt::kyc_denied(),
            0,
            b"blocked",
        );
        rt::transfer(&mut asset, &mut alice, &mut bob, 1, vector[], ctx);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 21, location = regulated_account::regulated_account)]
fun nonzero_fee_requires_receiver() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);

        rt::set_fee_config(&mut asset, &fee_cap, 1, 0, option::none());

        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 43, location = regulated_account::regulated_account)]
fun privacy_assets_reject_public_max_supply_cap() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        rt::set_max_supply(&mut asset, &mint_cap, option::some(100));

        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);
        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::freeze_account(&asset, &freeze_cap, &mut account);
        assert!(rt::frozen(&account), 0);
        rt::thaw(&asset, &freeze_cap, &mut account);
        assert!(!rt::frozen(&account), 1);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun privacy_initializes_identity_commitments() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);

        let account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        let identity = ristretto255::g_identity();
        assert!(group_ops::equal(&rt::confidential_available(&account), &identity), 0);
        assert!(group_ops::equal(&rt::confidential_pending(&account), &identity), 1);
        assert!(group_ops::equal(&rt::confidential_supply(&asset), &identity), 2);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);
        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut account, 100);
        assert!(rt::raw_balance(&account) == 100, 0);
        assert!(rt::display_balance(&asset, &account) == 100, 1);
        assert!(rt::display_supply(&asset) == 100, 2);

        rt::set_display_scale(&mut asset, &policy_cap, 2, 1);
        let (num, den) = rt::display_scale(&asset);
        assert!(num == 2, 3);
        assert!(den == 1, 4);
        assert!(rt::raw_balance(&account) == 100, 5);
        assert!(rt::display_balance(&asset, &account) == 200, 6);
        assert!(rt::display_supply(&asset) == 200, 7);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 34, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);
        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::set_max_supply(&mut asset, &mint_cap, option::some(100));
        let max_supply = rt::max_supply(&asset);
        assert!(max_supply.is_some(), 0);
        assert!(*max_supply.borrow() == 100, 1);
        rt::mint(&mut asset, &mint_cap, &mut account, 101);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 25, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut account, std::u64::max_value!());
        rt::set_display_scale(&mut asset, &policy_cap, 2, 1);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 36, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::set_shareholder_caps(&mut asset, &policy_cap, option::some(1));
        rt::mint(&mut asset, &mint_cap, &mut alice, 10);
        assert!(rt::total_shareholders(&asset) == 1, 0);
        rt::mint(&mut asset, &mint_cap, &mut bob, 10);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), false, ctx);

        let identity = rt::identity_external(@0x1D);
        let mut wallet_a = rt::new_account_for_testing_with_identity(
            &asset,
            rt::holder_address(ctx.sender()),
            identity,
            true,
            true,
            ctx,
        );
        let mut wallet_b = rt::new_account_for_testing_with_identity(
            &asset,
            rt::holder_address(@0xB0B),
            identity,
            true,
            true,
            ctx,
        );

        rt::set_shareholder_caps(&mut asset, &policy_cap, option::some(1));
        rt::mint(&mut asset, &mint_cap, &mut wallet_a, 10);
        rt::mint(&mut asset, &mint_cap, &mut wallet_b, 20);

        assert!(rt::total_shareholders(&asset) == 1, 0);
        assert!(rt::identity_positive_account_count(&asset, identity) == 2, 1);

        unit_test::destroy(wallet_a);
        unit_test::destroy(wallet_b);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 9, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut alice, 100);
        rt::set_locked_balance(&asset, &freeze_cap, &mut alice, 80);
        assert!(rt::transferable_balance(&alice) == 20, 0);
        rt::transfer(&mut asset, &mut alice, &mut bob, 25, vector[], ctx);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint_restricted(&mut asset, &mint_cap, &mut alice, 100, 10_000, b"grant");
        rt::set_locked_balance(&asset, &freeze_cap, &mut alice, 100);
        rt::clawback(&mut asset, &clawback_cap, &mut alice, &mut bob, 100);

        assert!(rt::balance(&alice) == 0, 0);
        assert!(rt::balance(&bob) == 100, 1);
        assert!(rt::locked_balance(&alice) == 0, 2);
        assert!(rt::restricted_lot_count(&alice) == 0, 3);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun restricted_lot_unlocks_with_clock() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 1_000);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint_restricted(&mut asset, &mint_cap, &mut alice, 100, 1_000, b"rule-144");
        assert!(rt::restricted_lot_count(&alice) == 1, 0);
        assert!(rt::transferable_balance(&alice) == 0, 1);
        assert!(rt::transferable_balance_with_clock(&alice, &clock) == 100, 2);

        rt::transfer_with_clock(&mut asset, &mut alice, &mut bob, 60, vector[], &clock, ctx);
        assert!(rt::balance(&alice) == 40, 3);
        assert!(rt::balance(&bob) == 60, 4);
        assert!(rt::restricted_lot_count(&alice) == 0, 5);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        clock::destroy_for_testing(clock);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        rt::set_default_account_frozen(&mut asset, &policy_cap, true);
        assert!(rt::default_account_frozen(&asset), 0);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        assert!(rt::frozen(&account), 1);

        rt::thaw(&asset, &freeze_cap, &mut account);
        assert!(!rt::frozen(&account), 2);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun metadata_and_group_pointers_are_mutable_hooks() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);
        let metadata_cap = rt::new_metadata_cap_for_testing(&asset, ctx);

        let account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let account_id = rt::account_id(&account);
        let asset_id = rt::asset_id(&asset);

        rt::set_metadata_pointer(&mut asset, &metadata_cap, option::some(account_id));
        rt::set_group_pointers(&mut asset, &policy_cap, option::some(asset_id), option::some(account_id));

        let metadata_pointer = rt::metadata_pointer(&asset);
        assert!(metadata_pointer.is_some(), 0);
        assert!(*metadata_pointer.borrow() == account_id, 1);

        let group_pointer = rt::group_pointer(&asset);
        assert!(group_pointer.is_some(), 2);
        assert!(*group_pointer.borrow() == asset_id, 3);

        let group_member_pointer = rt::group_member_pointer(&asset);
        assert!(group_member_pointer.is_some(), 4);
        assert!(*group_member_pointer.borrow() == account_id, 5);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(metadata_cap);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun scaled_ui_amount_is_ui_state() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        rt::set_scaled_ui_amount(&mut asset, &policy_cap, 3, 2);
        let (num, den) = rt::display_scale(&asset);
        assert!(num == 3, 0);
        assert!(den == 2, 1);

        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 29, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);
        let pause_cap = rt::new_pause_cap_for_testing(&asset, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut alice, 100);
        rt::pause(&mut asset, &pause_cap);
        assert!(rt::paused(&asset), 0);
        rt::transfer(&mut asset, &mut alice, &mut bob, 1, vector[], ctx);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(pause_cap);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 30, location = regulated_account::regulated_account)]
fun non_transferable_blocks_transfers() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::enable_non_transferable(&mut asset, &policy_cap);
        assert!(rt::non_transferable(&asset), 0);
        rt::mint(&mut asset, &mint_cap, &mut alice, 100);
        rt::transfer(&mut asset, &mut alice, &mut bob, 1, vector[], ctx);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 26, location = regulated_account::regulated_account)]
fun holder_change_requires_empty_confidential_pending() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);
        let registration_cap = rt::new_registration_cap_for_testing(&asset, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        rt::add_pending_note_for_testing(&mut account, b"pending", vector[]);
        rt::set_holder(
            &asset,
            &registration_cap,
            &mut account,
            rt::holder_address(@0xB0B),
            vector[],
            vector[],
            b"court-order-hash",
        );

        unit_test::destroy(account);
        unit_test::destroy(registration_cap);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 27, location = regulated_account::regulated_account)]
fun confidential_pending_notes_are_bounded() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        let mut i = 0;
        while (i < rt::max_pending_confidential_notes()) {
            rt::add_pending_note_for_testing(&mut account, b"pending", vector[]);
            i = i + 1;
        };
        assert!(rt::pending_confidential_note_count(&account) == rt::max_pending_confidential_notes(), 0);
        rt::add_pending_note_for_testing(&mut account, b"overflow", vector[]);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 27, location = regulated_account::regulated_account)]
fun confidential_pending_notes_respect_account_limit() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::admin_set_confidential_pending_limit(&asset, &policy_cap, &mut account, 1);
        assert!(rt::account_max_pending_confidential_notes(&account) == 1, 0);
        rt::add_pending_note_for_testing(&mut account, b"one", vector[]);
        rt::add_pending_note_for_testing(&mut account, b"two", vector[]);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 1, location = sui::rangeproofs)]
fun admin_apply_pending_confidential_does_not_require_holder_owner() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );
        rt::add_pending_note_for_testing(&mut account, b"pending", vector[]);
        rt::admin_apply_pending_confidential(
            &asset,
            &policy_cap,
            &mut account,
            x"e2f2ae0a6abc4e71a884a961c500515f58e30b6aa582dd8db6a65945e08d2d76",
            vector[],
            b"owner-opening",
            vector[],
        );

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );
        let mut fees = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xFEE),
            true,
            true,
            ctx,
        );

        rt::set_fee_config(
            &mut asset,
            &fee_cap,
            1_000,
            5,
            option::some(rt::account_id(&fees)),
        );
        rt::mint(&mut asset, &mint_cap, &mut alice, 1_000);
        rt::transfer_with_fee_account(&mut asset, &mut alice, &mut bob, &mut fees, 100, vector[], ctx);

        assert!(rt::balance(&alice) == 900, 0);
        assert!(rt::balance(&bob) == 85, 1);
        assert!(rt::balance(&fees) == 15, 2);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(fees);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun transfer_request_with_external_rule_confirms_transfer() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::add_transfer_rule<TEST, ExternalRule>(&mut asset, &policy_cap);
        assert!(rt::transfer_rule_count(&asset) == 1, 0);
        assert!(rt::has_transfer_rule<TEST, ExternalRule>(&asset), 1);

        rt::mint(&mut asset, &mint_cap, &mut alice, 500);
        let mut request = rt::request_transfer(&asset, &alice, &bob, 125, b"approved", ctx);
        assert!(rt::transfer_request_asset_id(&request) == rt::asset_id(&asset), 2);
        assert!(rt::transfer_request_from_account(&request) == rt::account_id(&alice), 3);
        assert!(rt::transfer_request_to_account(&request) == rt::account_id(&bob), 4);
        assert!(rt::transfer_request_amount(&request) == 125, 5);
        assert!(rt::transfer_request_memo(&request) == b"approved", 6);

        rt::add_transfer_rule_approval<TEST, ExternalRule>(ExternalRule {}, &mut request);
        rt::confirm_transfer(&mut asset, &mut alice, &mut bob, request);

        assert!(rt::balance(&alice) == 375, 7);
        assert!(rt::balance(&bob) == 125, 8);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 31, location = regulated_account::regulated_account)]
fun configured_transfer_rule_blocks_direct_transfer() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::add_transfer_rule<TEST, ExternalRule>(&mut asset, &policy_cap);
        rt::mint(&mut asset, &mint_cap, &mut alice, 500);
        rt::transfer(&mut asset, &mut alice, &mut bob, 125, vector[], ctx);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 31, location = regulated_account::regulated_account)]
fun configured_transfer_rule_blocks_direct_confidential_transfer() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::add_transfer_rule<TEST, ExternalRule>(&mut asset, &policy_cap);
        rt::confidential_transfer(
            &asset,
            &mut alice,
            &mut bob,
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            ctx,
        );

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 32, location = regulated_account::regulated_account)]
fun transfer_request_requires_all_rule_approvals() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::add_transfer_rule<TEST, ExternalRule>(&mut asset, &policy_cap);
        rt::mint(&mut asset, &mint_cap, &mut alice, 500);
        let request = rt::request_transfer(&asset, &alice, &bob, 125, vector[], ctx);
        rt::confirm_transfer(&mut asset, &mut alice, &mut bob, request);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 32, location = regulated_account::regulated_account)]
fun confidential_transfer_request_requires_all_rule_approvals() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::add_transfer_rule<TEST, ExternalRule>(&mut asset, &policy_cap);
        let request = rt::request_confidential_transfer(
            &asset,
            &alice,
            &bob,
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            ctx,
        );
        rt::confirm_confidential_transfer(&asset, &mut alice, &mut bob, request);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun object_owned_account_can_transfer_with_authority() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let authority = new_authority(ctx);
        rt::authorize_object_holder(&mut asset, &policy_cap, object::id(&authority));
        let mut program_account = rt::new_account_for_testing(
            &asset,
            rt::holder_object(object::id(&authority)),
            true,
            true,
            ctx,
        );
        let mut user_account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut program_account, 500);
        rt::transfer_with_object_authority(
            &mut asset,
            &authority,
            &mut program_account,
            &mut user_account,
            125,
            vector[],
        );

        assert!(rt::balance(&program_account) == 375, 0);
        assert!(rt::balance(&user_account) == 125, 1);

        unit_test::destroy(authority);
        unit_test::destroy(program_account);
        unit_test::destroy(user_account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 7, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::freeze_account(&asset, &freeze_cap, &mut account);
        rt::mint(&mut asset, &mint_cap, &mut account, 1);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 8, location = regulated_account::regulated_account)]
fun confidential_mint_to_denied_holder_fails_before_proofs() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::denylist_mode(), true, ctx);

        let holder = rt::holder_address(@0xB0B);
        let mut account = rt::new_account_for_testing(&asset, holder, true, true, ctx);
        rt::set_kyc(
            &mut asset,
            &policy_cap,
            rt::identity_from_holder(holder),
            rt::kyc_denied(),
            0,
            b"deny",
        );

        rt::confidential_mint(
            &mut asset,
            &mint_cap,
            &mut account,
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
        );

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 17, location = regulated_account::regulated_account)]
fun invalid_confidential_commitment_length_uses_module_error() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::confidential_mint(
            &mut asset,
            &mint_cap,
            &mut account,
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
        );

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 40, location = regulated_account::regulated_account)]
fun shareholder_caps_disable_confidential_amount_lane() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );

        rt::set_shareholder_caps(&mut asset, &policy_cap, option::some(10));
        rt::confidential_mint(
            &mut asset,
            &mint_cap,
            &mut account,
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
            vector[],
        );

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 8, location = regulated_account::regulated_account)]
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
        ) = rt::new_asset_for_testing<TEST>(rt::allowlist_mode(), true, ctx);

        let holder = rt::holder_address(ctx.sender());
        rt::set_kyc(
            &mut asset,
            &policy_cap,
            rt::identity_from_holder(holder),
            rt::kyc_approved(),
            100,
            b"kyc",
        );
        let account = rt::new_account_for_testing(&asset, holder, true, true, ctx);

        unit_test::destroy(account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun expiring_kyc_works_with_clock_before_expiry() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::allowlist_mode(), true, ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 50);

        let holder = rt::holder_address(ctx.sender());
        rt::set_kyc(
            &mut asset,
            &policy_cap,
            rt::identity_from_holder(holder),
            rt::kyc_approved(),
            100,
            b"kyc",
        );
        let account = rt::new_account_for_testing_with_clock(
            &asset,
            holder,
            true,
            true,
            &clock,
            ctx,
        );

        assert!(rt::balance(&account) == 0, 0);

        unit_test::destroy(account);
        clock::destroy_for_testing(clock);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let mut alice = rt::new_account_for_testing(
            &asset,
            rt::holder_address(ctx.sender()),
            true,
            true,
            ctx,
        );
        let mut bob = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );
        let mut fees = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xFEE),
            true,
            true,
            ctx,
        );

        rt::set_fee_config(
            &mut asset,
            &fee_cap,
            10_000,
            0,
            option::some(rt::account_id(&fees)),
        );
        let max = std::u64::max_value!();
        rt::mint(&mut asset, &mint_cap, &mut alice, max);
        rt::transfer_with_fee_account(&mut asset, &mut alice, &mut bob, &mut fees, max, vector[], ctx);

        assert!(rt::balance(&alice) == 0, 0);
        assert!(rt::balance(&bob) == 0, 1);
        assert!(rt::balance(&fees) == max, 2);

        unit_test::destroy(alice);
        unit_test::destroy(bob);
        unit_test::destroy(fees);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = regulated_account::regulated_account)]
fun object_owned_account_requires_authorized_object_id() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let authority = new_authority(ctx);
        let mut program_account = rt::new_account_for_testing(
            &asset,
            rt::holder_object(object::id(&authority)),
            true,
            true,
            ctx,
        );
        let mut user_account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut program_account, 500);
        rt::transfer_with_object_authority(
            &mut asset,
            &authority,
            &mut program_account,
            &mut user_account,
            125,
            vector[],
        );

        unit_test::destroy(authority);
        unit_test::destroy(program_account);
        unit_test::destroy(user_account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun package_witness_authority_is_exact_type() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        rt::authorize_witness<TEST, ProgramWitness>(&mut asset, &policy_cap);

        let mut program_account = rt::new_account_for_testing(
            &asset,
            rt::holder_package(type_name::original_id<ProgramWitness>()),
            true,
            true,
            ctx,
        );
        let mut user_account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut program_account, 500);
        rt::transfer_with_package_witness<TEST, ProgramWitness>(
            &mut asset,
            ProgramWitness {},
            &mut program_account,
            &mut user_account,
            125,
            vector[],
        );

        assert!(rt::balance(&program_account) == 375, 0);
        assert!(rt::balance(&user_account) == 125, 1);

        unit_test::destroy(program_account);
        unit_test::destroy(user_account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 6, location = regulated_account::regulated_account)]
fun unauthorized_witness_from_same_package_fails() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        rt::authorize_witness<TEST, ProgramWitness>(&mut asset, &policy_cap);

        let mut program_account = rt::new_account_for_testing(
            &asset,
            rt::holder_package(type_name::original_id<ProgramWitness>()),
            true,
            true,
            ctx,
        );
        let mut user_account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut program_account, 500);
        rt::transfer_with_package_witness<TEST, OtherWitness>(
            &mut asset,
            OtherWitness {},
            &mut program_account,
            &mut user_account,
            125,
            vector[],
        );

        unit_test::destroy(program_account);
        unit_test::destroy(user_account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun permanently_authorized_package_allows_wrapper_witnesses() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let wrapper_package = type_name::original_id<ProgramWitness>();
        rt::permanently_authorize_package<TEST>(&mut asset, &policy_cap, wrapper_package);

        let mut wrapper_account = rt::new_account_for_testing(
            &asset,
            rt::holder_package(wrapper_package),
            true,
            true,
            ctx,
        );
        let mut user_account = rt::new_account_for_testing(
            &asset,
            rt::holder_address(@0xB0B),
            true,
            true,
            ctx,
        );

        rt::mint(&mut asset, &mint_cap, &mut wrapper_account, 500);
        rt::transfer_with_package_witness<TEST, OtherWitness>(
            &mut asset,
            OtherWitness {},
            &mut wrapper_account,
            &mut user_account,
            125,
            vector[],
        );

        assert!(rt::balance(&wrapper_account) == 375, 0);
        assert!(rt::balance(&user_account) == 125, 1);

        unit_test::destroy(wrapper_account);
        unit_test::destroy(user_account);
        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 24, location = regulated_account::regulated_account)]
fun permanently_authorized_package_cannot_be_downgraded() {
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
        ) = rt::new_asset_for_testing<TEST>(rt::open_mode(), true, ctx);

        let wrapper_package = type_name::original_id<ProgramWitness>();
        rt::permanently_authorize_package<TEST>(&mut asset, &policy_cap, wrapper_package);
        rt::authorize_package<TEST>(&mut asset, &policy_cap, wrapper_package);

        unit_test::destroy(asset);
        unit_test::destroy(mint_cap);
        unit_test::destroy(policy_cap);
        unit_test::destroy(freeze_cap);
        unit_test::destroy(burn_cap);
        unit_test::destroy(clawback_cap);
        unit_test::destroy(fee_cap);
        unit_test::destroy(close_cap);
    };
    ts::end(scenario);
}
