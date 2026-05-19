#[test_only]
module regulated_account::shareholder_tests;

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

        asset_policy::set_shareholder_caps(&mut asset, &policy_cap, option::some(1), b"holder-cap");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            10,
        );
        assert_eq!(asset::total_shareholders(&asset), 1);
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut bob,
            10,
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        let identity = keys::identity_external(@0x1D);
        let mut wallet_a = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_package(@0xA11CE),
            identity,
            true,
            ctx,
        );
        let mut wallet_b = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_package(@0xB0B),
            identity,
            true,
            ctx,
        );

        asset_policy::set_shareholder_caps(&mut asset, &policy_cap, option::some(1), b"holder-cap");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut wallet_a,
            10,
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut wallet_b,
            20,
        );

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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let registration_cap = test_helpers::new_registration_cap(&asset, ctx);

        let old_identity = keys::identity_external(@0xCAFE);
        let new_identity = keys::identity_external(@0xC0FFEE);
        let mut account = test_helpers::new_account_with_identity(
            &asset,
            keys::holder_package(@0xF00D),
            old_identity,
            true,
            ctx,
        );

        asset_policy::set_shareholder_caps(&mut asset, &policy_cap, option::some(1), b"holder-cap");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            100,
        );
        account_policy::set_identity(
            &mut asset,
            &registration_cap,
            authority::no_time(),
            vector[],
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        assert_eq!(asset::min_positive_balance(&asset), 100);
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            99,
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

        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            150,
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut bob,
            100,
        );
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            60,
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

#[test, expected_failure(abort_code = 34, location = regulated_account::shareholders)]
fun min_positive_balance_increase_requires_no_positive_accounts() {
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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            100,
        );
        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 1, b"raise-min");

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

#[test]
fun min_positive_balance_can_increase_after_all_accounts_exit() {
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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            100,
        );
        ledger::burn(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut account,
            100,
        );
        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 200, b"raise-min");

        assert_eq!(asset::min_positive_balance(&asset), 200);
        assert_eq!(account::balance(&account), 0);
        assert_eq!(asset::total_shareholders(&asset), 0);

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

#[test]
fun min_positive_balance_can_decrease_with_positive_accounts() {
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

        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            100,
        );
        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 50, b"lower-min");

        assert_eq!(asset::min_positive_balance(&asset), 50);
        assert_eq!(account::balance(&account), 100);

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

        asset_policy::set_min_positive_balance(&mut asset, &policy_cap, 100, b"min-balance");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            150,
        );
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            150,
            vector[],
        );

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
        destroy(close_cap);
    };
    ts::end(scenario);
}
