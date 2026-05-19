#[test_only]
module regulated_account::lifecycle_tests;

use regulated_account::account;
use regulated_account::account_policy;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::asset_policy;
use regulated_account::keys;
use regulated_account::ledger;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::unit_test::{assert_eq, destroy};
use sui::test_scenario as ts;

public struct TEST has drop {}

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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            1_000,
        );
        assert_eq!(account::balance(&alice), 1_000);
        assert_eq!(asset::supply(&asset), 1_000);

        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            250,
            vector[],
        );
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        asset_policy::set_max_supply(&mut asset, &mint_cap, option::some(100), b"max-supply");
        let max_supply = asset::max_supply(&asset);
        assert!(max_supply.is_some(), 0);
        assert_eq!(*max_supply.borrow(), 100);
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            101,
        );

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 25, location = regulated_account::amount_math)]
fun decrease_supply_underflow_uses_amount_math_error() {
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        asset::decrease_supply(&mut asset, 1);

        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            0,
        );

        destroy(alice);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 33, location = regulated_account::validation)]
fun zero_amount_transfer_rejected() {
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

        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            0,
            vector[],
        );

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 33, location = regulated_account::validation)]
fun zero_amount_public_burn_rejected() {
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            10,
        );

        ledger::burn(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            0,
        );

        destroy(alice);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 33, location = regulated_account::validation)]
fun zero_amount_admin_burn_rejected() {
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            10,
        );

        ledger::admin_burn(&mut asset, &burn_cap, &mut alice, 0, b"admin-burn");

        destroy(alice);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        account_policy::freeze_account(&mut asset, &freeze_cap, &mut account, b"freeze");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            1,
        );

        destroy(account);
        destroy(asset);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}
