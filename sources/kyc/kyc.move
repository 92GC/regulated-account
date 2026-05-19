module regulated_account::kyc;

use regulated_account::constants;

const EInvalidKycStatus: u64 = 26;

public struct KycRecord has copy, drop, store {
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
}

public fun unknown(): u8 { constants::kyc_unknown() }
public fun approved(): u8 { constants::kyc_approved() }
public fun denied(): u8 { constants::kyc_denied() }
public fun pending(): u8 { constants::kyc_pending() }
public fun expired(): u8 { constants::kyc_expired() }
public fun exempt(): u8 { constants::kyc_exempt() }
public fun divest_only(): u8 { constants::kyc_divest_only() }

public(package) fun new(
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
): KycRecord {
    assert_valid_status(status);
    KycRecord { status, expires_ms, external_ref_hash }
}

public(package) fun assert_valid_status(status: u8) {
    assert!(
        status == constants::kyc_unknown() ||
            status == constants::kyc_approved() ||
            status == constants::kyc_denied() ||
            status == constants::kyc_pending() ||
            status == constants::kyc_expired() ||
            status == constants::kyc_exempt() ||
            status == constants::kyc_divest_only(),
        EInvalidKycStatus,
    );
}

public(package) fun status(record: &KycRecord): u8 { record.status }
public(package) fun expires_ms(record: &KycRecord): u64 { record.expires_ms }
public(package) fun external_ref_hash(record: &KycRecord): vector<u8> { record.external_ref_hash }

public(package) fun effective_status(record: &KycRecord, now_ms: &Option<u64>): u8 {
    if (record.expires_ms == 0) {
        record.status
    } else if (now_ms.is_some() && *now_ms.borrow() <= record.expires_ms) {
        record.status
    } else {
        constants::kyc_expired()
    }
}

public(package) fun approved_now(record: &KycRecord, now_ms: &Option<u64>): bool {
    let status = effective_status(record, now_ms);
    status == constants::kyc_approved() || status == constants::kyc_exempt()
}

public(package) fun credit_allowed(record: &KycRecord, now_ms: &Option<u64>): bool {
    let status = effective_status(record, now_ms);
    status == constants::kyc_approved() ||
        status == constants::kyc_exempt() ||
        status == constants::kyc_pending()
}

public(package) fun debit_allowed(record: &KycRecord, now_ms: &Option<u64>): bool {
    let status = effective_status(record, now_ms);
    status == constants::kyc_approved() ||
        status == constants::kyc_exempt() ||
        status == constants::kyc_divest_only()
}
