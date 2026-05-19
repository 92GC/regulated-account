#[test_only]
module regulated_account::policy_tests;

use regulated_account::account;
use regulated_account::account_policy;
use regulated_account::asset;
use regulated_account::asset_policy;
use regulated_account::authority;
use regulated_account::keys;
use regulated_account::kyc;
use regulated_account::kyc_admin;
use regulated_account::ledger;
use regulated_account::regulated_account as ra;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::unit_test::{assert_eq, destroy};
use sui::clock;
use sui::test_scenario as ts;

public struct TEST has drop {}

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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            identity,
            kyc::approved(),
            0,
            b"kyc-ref",
        );
        assert!(asset::has_kyc(&asset, identity), 0);
        assert_eq!(asset::kyc_status(&asset, identity), kyc::approved());
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        kyc_admin::set_kyc(
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
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 7, location = regulated_account::kyc_policy)]
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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            100,
        );
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(alice_holder),
            kyc::denied(),
            0,
            b"blocked",
        );
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            1,
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

#[test, expected_failure(abort_code = 7, location = regulated_account::kyc_policy)]
fun expired_explicit_kyc_blocks_even_in_denylist_mode() {
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
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 200);

        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            identity,
            kyc::approved(),
            100,
            b"expired-approval",
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
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test]
fun pending_before_expiry_can_create_and_receive() {
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
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 50);

        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            identity,
            kyc::pending(),
            100,
            b"pending-review",
        );

        let mut account = test_helpers::new_account_at_time(
            &asset,
            holder,
            true,
            authority::clock_time(&clock),
            ctx,
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            vector[],
            &mut account,
            100,
        );

        assert_eq!(account::balance(&account), 100);

        destroy(account);
        clock::destroy_for_testing(clock);
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
fun pending_before_expiry_cannot_debit() {
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
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 50);

        let alice_holder = keys::holder_address(ctx.sender());
        let alice_identity = keys::identity_from_holder(alice_holder);
        let bob_holder = keys::holder_address(@0xB0B);
        let bob_identity = keys::identity_from_holder(bob_holder);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            alice_identity,
            kyc::pending(),
            100,
            b"alice-pending",
        );
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            bob_identity,
            kyc::approved(),
            0,
            b"bob-approved",
        );

        let mut alice = test_helpers::new_account_at_time(
            &asset,
            alice_holder,
            true,
            authority::clock_time(&clock),
            ctx,
        );
        let mut bob = test_helpers::new_account_at_time(
            &asset,
            bob_holder,
            true,
            authority::clock_time(&clock),
            ctx,
        );
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            vector[],
            &mut alice,
            100,
        );
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::clock_time(&clock),
            vector[],
            &mut alice,
            &mut bob,
            1,
            vector[],
        );

        destroy(alice);
        destroy(bob);
        clock::destroy_for_testing(clock);
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
fun pending_after_expiry_is_effectively_expired() {
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
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);
        let mut asset = asset;
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 200);

        let holder = keys::holder_address(ctx.sender());
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(holder),
            kyc::pending(),
            100,
            b"pending-expired",
        );
        let account = test_helpers::new_account_at_time(
            &asset,
            holder,
            true,
            authority::clock_time(&clock),
            ctx,
        );

        destroy(account);
        clock::destroy_for_testing(clock);
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
fun divest_only_can_debit_but_not_receive() {
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
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let alice_holder = keys::holder_address(ctx.sender());
        let alice_identity = keys::identity_from_holder(alice_holder);
        let bob_holder = keys::holder_address(@0xB0B);
        let bob_identity = keys::identity_from_holder(bob_holder);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            alice_identity,
            kyc::approved(),
            0,
            b"alice-approved",
        );
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            bob_identity,
            kyc::approved(),
            0,
            b"bob-approved",
        );

        let mut alice = test_helpers::new_account(&asset, alice_holder, true, ctx);
        let mut bob = test_helpers::new_account(&asset, bob_holder, true, ctx);
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            100,
        );
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            alice_identity,
            kyc::divest_only(),
            0,
            b"divest",
        );
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            40,
            vector[],
        );

        assert_eq!(account::balance(&alice), 60);
        assert_eq!(account::balance(&bob), 40);

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
fun divest_only_cannot_receive() {
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
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            identity,
            kyc::approved(),
            0,
            b"approved",
        );
        let mut account = test_helpers::new_account(&asset, holder, true, ctx);
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            identity,
            kyc::divest_only(),
            0,
            b"divest",
        );
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        asset_policy::lock_compliance_mode(&mut asset, &policy_cap, b"lock-mode");
        asset_policy::set_compliance_mode(&mut asset, &policy_cap, asset::denylist_mode(), b"change-mode");

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
fun freeze_and_thaw_account() {
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
        assert!(account::frozen(&account), 0);
        assert!(asset::identity_frozen(&asset, account::identity(&account)), 1);
        account_policy::thaw(&mut asset, &freeze_cap, &mut account, b"thaw");
        assert!(!account::frozen(&account), 2);
        assert!(!asset::identity_frozen(&asset, account::identity(&account)), 3);

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

#[test, expected_failure(abort_code = 6, location = regulated_account::asset)]
fun frozen_identity_cannot_create_fresh_account() {
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
        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        let mut account = test_helpers::new_account(&asset, holder, true, ctx);

        account_policy::freeze_account(&mut asset, &freeze_cap, &mut account, b"freeze");
        ra::create_account(
            &asset,
            authority::no_time(),
            vector[],
            holder,
            identity,
            option::none(),
            false,
            true,
            ctx,
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);

        asset_policy::set_default_account_frozen(&mut asset, &policy_cap, true, b"default-frozen");
        assert!(asset::default_account_frozen(&asset), 0);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );
        assert!(account::frozen(&account), 1);

        account_policy::thaw(&mut asset, &freeze_cap, &mut account, b"thaw");
        assert!(!account::frozen(&account), 2);

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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            100,
        );
        asset_policy::pause(&mut asset, &pause_cap, b"pause");
        assert!(asset::paused(&asset), 0);
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            &mut bob,
            1,
            vector[],
        );

        destroy(alice);
        destroy(bob);
        destroy(asset);
        destroy(pause_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

        let mut alice = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        asset_policy::pause(&mut asset, &pause_cap, b"pause");
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            1,
        );

        destroy(alice);
        destroy(asset);
        destroy(pause_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

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
        asset_policy::pause(&mut asset, &pause_cap, b"pause");
        ledger::burn(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            vector[],
            &mut alice,
            1,
        );

        destroy(alice);
        destroy(asset);
        destroy(pause_cap);
        destroy(mint_cap);
        destroy(policy_cap);
        destroy(freeze_cap);
        destroy(burn_cap);
        destroy(clawback_cap);
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 18, location = regulated_account::asset)]
fun pause_cap_blocks_admin_account_creation() {
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
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);
        let registration_cap = test_helpers::new_registration_cap(&asset, ctx);
        let holder = keys::holder_address(@0xB0B);

        asset_policy::pause(&mut asset, &pause_cap, b"pause");
        ra::admin_create_account(
            &asset,
            &registration_cap,
            authority::no_time(),
            vector[],
            holder,
            keys::identity_from_holder(holder),
            option::none(),
            false,
            false,
            true,
            ctx,
        );

        destroy(asset);
        destroy(pause_cap);
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

#[test]
fun pause_cap_allows_admin_burn() {
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
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

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
            10,
        );
        asset_policy::pause(&mut asset, &pause_cap, b"pause");
        ledger::admin_burn(&mut asset, &burn_cap, &mut account, 4, b"admin-burn");

        assert_eq!(account::balance(&account), 6);
        assert_eq!(asset::supply(&asset), 6);

        destroy(account);
        destroy(asset);
        destroy(pause_cap);
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
fun pause_cap_allows_clawback() {
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
        let pause_cap = test_helpers::new_pause_cap(&asset, ctx);

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

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            10,
        );
        asset_policy::pause(&mut asset, &pause_cap, b"pause");
        ledger::clawback(
            &mut asset,
            &clawback_cap,
            authority::no_time(),
            vector[],
            &mut alice,
            &mut recovery,
            4,
            b"clawback",
        );

        assert_eq!(account::balance(&alice), 6);
        assert_eq!(account::balance(&recovery), 4);

        destroy(alice);
        destroy(recovery);
        destroy(asset);
        destroy(pause_cap);
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);

        let holder = keys::holder_address(ctx.sender());
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(holder),
            kyc::approved(),
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
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::allowlist_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 50);

        let holder = keys::holder_address(ctx.sender());
        kyc_admin::set_kyc(
            &mut asset,
            &policy_cap,
            keys::identity_from_holder(holder),
            kyc::approved(),
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
        destroy(close_cap);
    };
    ts::end(scenario);
}

#[test, expected_failure(abort_code = 14, location = regulated_account::account)]
fun holder_lock_blocks_holder_change() {
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
        let registration_cap = test_helpers::new_registration_cap(&asset, ctx);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        account_policy::lock_holder(&asset, &registration_cap, &mut account, b"lock-holder");
        account_policy::set_holder(
            &asset,
            &registration_cap,
            &mut account,
            keys::holder_address(@0xB0B),
            b"holder-change",
        );

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

#[test, expected_failure(abort_code = 5, location = regulated_account::account)]
fun address_holder_identity_update_requires_matching_identity() {
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
        let new_identity = keys::identity_address(@0xC0FFEE);

        let mut account = test_helpers::new_account(
            &asset,
            keys::holder_address(ctx.sender()),
            true,
            ctx,
        );

        account_policy::set_identity(
            &mut asset,
            &registration_cap,
            authority::no_time(),
            vector[],
            &mut account,
            new_identity,
            b"identity-update",
        );

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
