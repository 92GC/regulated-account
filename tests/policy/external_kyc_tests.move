#[test_only]
module regulated_account::external_kyc_tests;

use regulated_account::account;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::constants;
use regulated_account::keys;
use regulated_account::kyc;
use regulated_account::kyc_admin;
use regulated_account::kyc_proof;
use regulated_account::kyc_registry;
use regulated_account::ledger;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::unit_test::{assert_eq, destroy};
use sui::clock;
use sui::test_scenario as ts;

public struct TEST has drop {}
public struct REGISTRY has drop {}

#[test]
fun registry_cap_can_be_destroyed_for_renunciation() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let registry_id = kyc_registry::id(&registry);
        assert_eq!(kyc_registry::cap_registry_id(&registry_cap), registry_id);

        kyc_registry::destroy_cap(registry_cap);
        kyc_registry::destroy_empty_registry_for_testing(registry);
    };
    ts::end(scenario);
}

#[test]
fun creation_time_trusted_registry_allows_allowlist_flow() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (mut registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let registry_id = kyc_registry::id(&registry);
        let source = kyc_registry::source<REGISTRY>(&registry);
        let config = kyc_proof::source_config(source, false);
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset_with_kyc_sources<TEST>(
            asset::allowlist_mode(),
            vector[config],
            ctx,
        );
        assert!(asset::trusted_kyc_source<TEST, REGISTRY>(&asset, registry_id), 0);

        let alice_holder = keys::holder_address(ctx.sender());
        let alice_identity = keys::identity_from_holder(alice_holder);
        let bob_holder = keys::holder_address(@0xB0B);
        let bob_identity = keys::identity_from_holder(bob_holder);
        kyc_registry::set_kyc(
            &mut registry,
            &registry_cap,
            alice_identity,
            kyc::approved(),
            0,
            b"alice-external",
        );
        kyc_registry::set_kyc(
            &mut registry,
            &registry_cap,
            bob_identity,
            kyc::approved(),
            0,
            b"bob-external",
        );

        let account_approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                alice_identity,
                authority::no_time(),
            ),
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                bob_identity,
                authority::no_time(),
            ),
        ];
        let mut alice = test_helpers::new_account_with_approvals(
            &asset,
            alice_holder,
            true,
            &account_approvals,
            ctx,
        );
        let mut bob = test_helpers::new_account_with_approvals(
            &asset,
            bob_holder,
            true,
            &account_approvals,
            ctx,
        );
        kyc_proof::destroy_all(account_approvals);

        let mint_approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                alice_identity,
                authority::no_time(),
            ),
        ];
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            mint_approvals,
            &mut alice,
            100,
        );
        let transfer_approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                alice_identity,
                authority::no_time(),
            ),
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                bob_identity,
                authority::no_time(),
            ),
        ];
        transfer_ops::transfer(
            &mut asset,
            authority::owner_authority<TEST>(ctx),
            authority::no_time(),
            transfer_approvals,
            &mut alice,
            &mut bob,
            40,
            vector[],
        );

        assert_eq!(account::balance(&alice), 60);
        assert_eq!(account::balance(&bob), 40);

        kyc_registry::remove_kyc(&mut registry, &registry_cap, alice_identity);
        kyc_registry::remove_kyc(&mut registry, &registry_cap, bob_identity);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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
fun required_external_source_approval_allows_allowlist_flow() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (mut registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let source = kyc_registry::source<REGISTRY>(&registry);
        let config = kyc_proof::source_config(source, true);
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset_with_kyc_sources<TEST>(
            asset::allowlist_mode(),
            vector[config],
            ctx,
        );
        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        kyc_registry::set_kyc(
            &mut registry,
            &registry_cap,
            identity,
            kyc::approved(),
            0,
            b"required-external",
        );

        let account_approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                identity,
                authority::no_time(),
            ),
        ];
        let mut account = test_helpers::new_account_with_approvals(
            &asset,
            holder,
            true,
            &account_approvals,
            ctx,
        );
        kyc_proof::destroy_all(account_approvals);

        let mint_approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                identity,
                authority::no_time(),
            ),
        ];
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            mint_approvals,
            &mut account,
            1,
        );
        assert_eq!(account::balance(&account), 1);

        kyc_registry::remove_kyc(&mut registry, &registry_cap, identity);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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

#[test, expected_failure(abort_code = 36, location = regulated_account::kyc_policy)]
fun too_many_kyc_approvals_are_rejected() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (mut registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
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
        kyc_registry::set_kyc(
            &mut registry,
            &registry_cap,
            identity,
            kyc::approved(),
            0,
            b"external",
        );

        let mut approvals = vector[];
        let mut i = 0;
        while (i <= constants::max_kyc_approvals()) {
            approvals.push_back(kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                identity,
                authority::no_time(),
            ));
            i = i + 1;
        };
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            approvals,
            &mut account,
            1,
        );

        kyc_registry::remove_kyc(&mut registry, &registry_cap, identity);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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

#[test, expected_failure(abort_code = 7, location = regulated_account::kyc_policy)]
fun expired_external_approval_is_rejected() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (mut registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let registry_id = kyc_registry::id(&registry);
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset<TEST>(asset::open_mode(), ctx);
        let mut clock = clock::create_for_testing(ctx);
        clock::set_for_testing(&mut clock, 0);
        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        let mut account = test_helpers::new_account(&asset, holder, true, ctx);

        kyc_admin::trust_kyc_source<TEST, REGISTRY>(
            &mut asset,
            &policy_cap,
            registry_id,
            true,
            b"trust-registry",
        );
        kyc_registry::set_kyc(
            &mut registry,
            &registry_cap,
            identity,
            kyc::approved(),
            5,
            b"external",
        );
        let approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                identity,
                authority::clock_time(&clock),
            ),
        ];
        clock::set_for_testing(&mut clock, 10);

        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::clock_time(&clock),
            approvals,
            &mut account,
            1,
        );

        kyc_registry::remove_kyc(&mut registry, &registry_cap, identity);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
        clock::destroy_for_testing(clock);
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
fun policy_cap_updates_trusted_kyc_source_for_asset_instance() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let registry_id = kyc_registry::id(&registry);
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
        assert_eq!(asset::trusted_kyc_source_count(&asset), 0);

        kyc_admin::trust_kyc_source<TEST, REGISTRY>(
            &mut asset,
            &policy_cap,
            registry_id,
            true,
            b"trust-registry",
        );
        assert!(asset::trusted_kyc_source<TEST, REGISTRY>(&asset, registry_id), 0);
        assert_eq!(asset::trusted_kyc_source_count(&asset), 1);
        assert!(asset::required_kyc_source<TEST, REGISTRY>(&asset, registry_id), 1);
        assert_eq!(asset::required_kyc_source_count(&asset), 1);

        kyc_admin::untrust_kyc_source<TEST, REGISTRY>(
            &mut asset,
            &policy_cap,
            registry_id,
            b"untrust-registry",
        );
        assert!(!asset::trusted_kyc_source<TEST, REGISTRY>(&asset, registry_id), 2);
        assert_eq!(asset::trusted_kyc_source_count(&asset), 0);
        assert_eq!(asset::required_kyc_source_count(&asset), 0);

        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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

#[test, expected_failure(abort_code = 35, location = regulated_account::kyc_policy)]
fun required_kyc_source_limit_rejects_extra_source() {
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

        let mut i = 0;
        while (i <= constants::max_required_kyc_sources()) {
            let id = object::new(ctx);
            let registry_id = object::uid_to_inner(&id);
            kyc_admin::trust_kyc_source<TEST, REGISTRY>(
                &mut asset,
                &policy_cap,
                registry_id,
                true,
                b"trust-registry",
            );
            id.delete();
            i = i + 1;
        };

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

#[test, expected_failure(abort_code = 35, location = regulated_account::kyc_policy)]
fun trusted_kyc_source_limit_rejects_extra_source() {
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

        let mut i = 0;
        while (i <= constants::max_trusted_kyc_sources()) {
            let id = object::new(ctx);
            let registry_id = object::uid_to_inner(&id);
            kyc_admin::trust_kyc_source<TEST, REGISTRY>(
                &mut asset,
                &policy_cap,
                registry_id,
                false,
                b"trust-registry",
            );
            id.delete();
            i = i + 1;
        };

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
fun required_external_source_blocks_open_mode_without_proof() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let source = kyc_registry::source<REGISTRY>(&registry);
        let config = kyc_proof::source_config(source, true);
        let (
            asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset_with_kyc_sources<TEST>(
            asset::open_mode(),
            vector[config],
            ctx,
        );
        let holder = keys::holder_address(ctx.sender());
        let account = test_helpers::new_account(&asset, holder, true, ctx);

        destroy(account);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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
fun required_external_source_blocks_native_only_kyc() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let source = kyc_registry::source<REGISTRY>(&registry);
        let config = kyc_proof::source_config(source, true);
        let (
            mut asset,
            mint_cap,
            policy_cap,
            freeze_cap,
            burn_cap,
            clawback_cap,
            close_cap,
        ) = test_helpers::new_asset_with_kyc_sources<TEST>(
            asset::allowlist_mode(),
            vector[config],
            ctx,
        );
        let holder = keys::holder_address(ctx.sender());
        let identity = keys::identity_from_holder(holder);
        kyc_admin::set_kyc(&mut asset, &policy_cap, identity, kyc::approved(), 0, b"native");

        let account = test_helpers::new_account(&asset, holder, true, ctx);

        destroy(account);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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
fun native_denial_blocks_external_approval() {
    let mut scenario = ts::begin(@0xA);
    {
        let ctx = scenario.ctx();
        let (mut registry, registry_cap) = kyc_registry::new_for_testing<REGISTRY>(ctx);
        let registry_id = kyc_registry::id(&registry);
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

        kyc_admin::trust_kyc_source<TEST, REGISTRY>(
            &mut asset,
            &policy_cap,
            registry_id,
            false,
            b"trust-registry",
        );
        kyc_registry::set_kyc(
            &mut registry,
            &registry_cap,
            identity,
            kyc::approved(),
            0,
            b"external",
        );
        kyc_admin::set_kyc(&mut asset, &policy_cap, identity, kyc::denied(), 0, b"deny");

        let approvals = vector[
            kyc_registry::approve<TEST, REGISTRY>(
                &asset,
                &registry,
                identity,
                authority::no_time(),
            ),
        ];
        ledger::mint(
            &mut asset,
            &mint_cap,
            authority::no_time(),
            approvals,
            &mut account,
            1,
        );

        kyc_registry::remove_kyc(&mut registry, &registry_cap, identity);
        kyc_registry::destroy_empty_for_testing(registry, registry_cap);
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
