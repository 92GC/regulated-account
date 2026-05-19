#[test_only]
module regulated_account::account_close_tests;

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

#[test]
fun close_non_empty_account_transfers_full_balance() {
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
        let source_identity = keys::identity_address(ctx.sender());
        let destination_identity = keys::identity_address(@0xB0B);
        let mut source = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut destination = test_helpers::new_account(
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
            &mut source,
            100,
        );
        transfer_ops::close_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            source,
            &mut destination,
            vector[],
        );

        assert_eq!(account::balance(&destination), 100);
        assert_eq!(asset::total_shareholders(&asset), 1);
        assert_eq!(asset::identity_positive_account_count(&asset, source_identity), 0);
        assert_eq!(asset::identity_positive_account_count(&asset, destination_identity), 1);

        destroy(destination);
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
fun close_empty_account_deletes_without_recipient() {
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
        let account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        transfer_ops::close_empty_account(
            &asset,
            authority::owner_authority<TEST>(ctx),
            account,
        );

        assert_eq!(asset::total_shareholders(&asset), 0);

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

#[test, expected_failure(abort_code = 35, location = regulated_account::account)]
fun close_empty_account_rejects_non_empty_account() {
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
            1,
        );
        transfer_ops::close_empty_account(
            &asset,
            authority::owner_authority<TEST>(ctx),
            account,
        );

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

#[test, expected_failure(abort_code = 8, location = regulated_account::account)]
fun close_non_empty_account_respects_static_lock() {
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
        let mut source = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let mut destination = test_helpers::new_account(
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
            &mut source,
            100,
        );
        account_policy::set_locked_balance(&asset, &freeze_cap, &mut source, 1, b"lock");
        transfer_ops::close_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            source,
            &mut destination,
            vector[],
        );

        destroy(destination);
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
fun close_non_empty_account_enforces_recipient_kyc() {
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
        let mut source = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        let denied_holder = keys::holder_address(@0xB0B);
        let mut destination = test_helpers::new_account(
            &asset,
            denied_holder,
            true,
            ctx,
        );

        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(denied_holder),
            kyc::denied(),
            0,
            b"denied",
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut source,
            100,
        );
        transfer_ops::close_account(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            source,
            &mut destination,
            vector[],
        );

        destroy(destination);
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
