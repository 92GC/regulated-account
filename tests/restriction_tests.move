#[test_only]
module regulated_account::restriction_tests;

use regulated_account::account;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::compliance;
use regulated_account::keys;
use regulated_account::ledger;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::unit_test::{assert_eq, destroy};
use sui::clock;
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
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
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
        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut account,
            max,
            10_000,
            b"grant",
        );
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

        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            100,
            10_000,
            b"grant",
        );
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
        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            50,
            20_000,
            b"grant-b",
        );
        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            60,
            10_000,
            b"grant-a",
        );
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
fun force_debit_trims_latest_unlocks_first() {
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
        let mut recovery = test_helpers::new_account(
            &asset,
            keys::holder_address(@0xFEE),
            true,
            ctx,
        );

        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 40, 20_000, b"late");
        ledger::mint_restricted(&mut asset, &mint_cap, authority::clock_time(&clock), &mut alice, 60, 10_000, b"early");
        ledger::clawback(&mut asset, &clawback_cap, &mut alice, &mut recovery, 50, b"clawback");

        assert_eq!(account::balance(&alice), 50);
        assert_eq!(account::restricted_locked_balance_at(&alice, authority::no_time()), 50);
        clock::set_for_testing(&mut clock, 15_000);
        assert_eq!(account::restricted_locked_balance_at(&alice, authority::clock_time(&clock)), 0);
        assert_eq!(account::transferable_balance_at(&alice, authority::clock_time(&clock)), 50);

        destroy(alice);
        destroy(recovery);
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

        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            100,
            1_000,
            b"rule-144",
        );
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

        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            40,
            10_000,
            b"same-grant",
        );
        ledger::mint_restricted(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            &mut alice,
            60,
            10_000,
            b"same-grant",
        );

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
