module regulated_account::authorization;

use regulated_account::account::{Self, Account};
use regulated_account::asset::{Self, Asset};
use regulated_account::authority::{Self, HolderAuthority};
use regulated_account::keys;
use regulated_account::kyc_proof::KycApproval;

const ENotAuthorized: u64 = 5;
const EPublicCreditDisabled: u64 = 13;

public(package) fun assert_public_credit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    assert!(account::allow_public_credits(account), EPublicCreditDisabled);
    asset::assert_identity_credit_allowed_with_approvals(
        asset,
        account::identity(account),
        now_ms,
        approvals,
    );
}

public(package) fun assert_public_debit_allowed<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    now_ms: &Option<u64>,
    approvals: &vector<KycApproval<T>>,
) {
    asset::assert_identity_debit_allowed_with_approvals(
        asset,
        account::identity(account),
        now_ms,
        approvals,
    );
}

public(package) fun assert_authorized<T>(
    asset: &Asset<T>,
    account: &Account<T>,
    holder_authority: HolderAuthority<T>,
) {
    let (kind, addr, witness) = authority::unpack(holder_authority);
    if (authority::is_owner(kind)) {
        assert!(keys::is_holder_address(account::holder(account)), ENotAuthorized);
        assert!(keys::holder_addr(account::holder(account)) == addr, ENotAuthorized);
    } else if (authority::is_package(kind)) {
        assert!(keys::is_holder_package(account::holder(account)), ENotAuthorized);
        assert!(keys::holder_addr(account::holder(account)) == addr, ENotAuthorized);
        assert!(witness.is_some(), ENotAuthorized);
        let witness_name = *witness.borrow();
        assert!(asset::witness_authorized(asset, witness_name), ENotAuthorized);
    } else {
        assert!(false, ENotAuthorized);
    };
}
