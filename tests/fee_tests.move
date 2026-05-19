#[test_only]
module regulated_account::fee_tests;

use regulated_account::account;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::compliance;
use regulated_account::keys;
use regulated_account::ledger;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::unit_test::{assert_eq, destroy};
use sui::test_scenario as ts;

public struct TEST has drop {}

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

#[test, expected_failure(abort_code = 16, location = regulated_account::transfer)]
fun configured_fee_requires_fee_path_even_when_bps_rounds_to_zero() {
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
fun plain_transfer_works_after_fee_config_is_cleared() {
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
        compliance::clear_fee_config(&mut asset, &fee_cap, b"clear-fee");

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
