#[test_only]
module regulated_account::lock_tests;

use regulated_account::account;
use regulated_account::account_policy;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::keys;
use regulated_account::kyc;
use regulated_account::kyc_admin;
use regulated_account::ledger;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::unit_test::{assert_eq, destroy};
use sui::test_scenario as ts;

public struct TEST has drop {}

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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            100,
        );
        account_policy::set_locked_balance(&asset, &freeze_cap, &mut alice, 80, b"lock");
        assert_eq!(account::transferable_balance(&alice), 20);
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            25,
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

#[test]
fun transferable_balance_saturates_when_fully_locked() {
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
        let max = std::u64::max_value!();
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut account,
            max,
        );
        account_policy::set_locked_balance(&asset, &freeze_cap, &mut account, max, b"lock");

        assert_eq!(account::transferable_balance(&account), 0);

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
fun clawback_reaches_locked_balance() {
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
            100,
        );
        account_policy::set_locked_balance(&asset, &freeze_cap, &mut alice, 100, b"lock");
        ledger::clawback(
            &mut asset,
            &clawback_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            100,
            b"clawback",
        );

        assert_eq!(account::balance(&alice), 0);
        assert_eq!(account::balance(&bob), 100);
        assert_eq!(account::locked_balance(&alice), 0);

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
fun partial_clawback_caps_locked_balance_to_remaining_balance() {
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
            200,
        );
        account_policy::set_locked_balance(&asset, &freeze_cap, &mut alice, 150, b"lock");
        ledger::clawback(
            &mut asset,
            &clawback_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            80,
            b"clawback",
        );

        assert_eq!(account::balance(&alice), 120);
        assert_eq!(account::locked_balance(&alice), 120);
        assert_eq!(account::transferable_balance(&alice), 0);
        assert_eq!(account::balance(&bob), 80);

        account_policy::set_locked_balance(&asset, &freeze_cap, &mut alice, 0, b"unlock");
        assert_eq!(account::transferable_balance(&alice), 120);

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

#[test, expected_failure(abort_code = 7, location = regulated_account::kyc_policy)]
fun clawback_enforces_recipient_kyc_for_admin_recovery() {
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
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(treasury_holder),
            kyc::denied(),
            0,
            b"treasury-denied",
        );

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            100,
        );
        ledger::clawback(
            &mut asset,
            &clawback_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            &mut treasury,
            25,
            b"clawback",
        );

        destroy(alice);
        destroy(treasury);
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
