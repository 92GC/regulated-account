#[test_only]
module regulated_account::wrapper_tests;

use regulated_account::account;
use regulated_account::asset;
use regulated_account::authority;
use regulated_account::compliance;
use regulated_account::keys;
use regulated_account::ledger;
use regulated_account::test_helpers;
use regulated_account::transfer as transfer_ops;
use std::type_name;
use std::unit_test::{assert_eq, destroy};
use sui::test_scenario as ts;

public struct TEST has drop {}
public struct WrapperWitness has drop {}
public struct TypedTerms<phantom T> has key {
    id: UID,
    asset_id: ID,
    account_id: ID,
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
