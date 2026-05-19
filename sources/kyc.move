module regulated_account::kyc;

const KYC_UNKNOWN: u8 = 0;
const KYC_APPROVED: u8 = 1;
const KYC_DENIED: u8 = 2;
const KYC_PENDING: u8 = 3;
const KYC_EXPIRED: u8 = 4;
const KYC_EXEMPT: u8 = 5;

const EInvalidKycStatus: u64 = 26;

public struct KycRecord has copy, drop, store {
    status: u8,
    expires_ms: u64,
    external_ref_hash: vector<u8>,
}

public fun unknown(): u8 { KYC_UNKNOWN }
public fun approved(): u8 { KYC_APPROVED }
public fun denied(): u8 { KYC_DENIED }
public fun pending(): u8 { KYC_PENDING }
public fun expired(): u8 { KYC_EXPIRED }
public fun exempt(): u8 { KYC_EXEMPT }

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
        status == KYC_UNKNOWN ||
            status == KYC_APPROVED ||
            status == KYC_DENIED ||
            status == KYC_PENDING ||
            status == KYC_EXPIRED ||
            status == KYC_EXEMPT,
        EInvalidKycStatus,
    );
}

public(package) fun status(record: &KycRecord): u8 { record.status }
public(package) fun expires_ms(record: &KycRecord): u64 { record.expires_ms }
public(package) fun external_ref_hash(record: &KycRecord): vector<u8> { record.external_ref_hash }

public(package) fun approved_now(record: &KycRecord, now_ms: &Option<u64>): bool {
    (record.status == KYC_APPROVED || record.status == KYC_EXEMPT) &&
        time_valid(record, now_ms)
}

public(package) fun not_denied_now(record: &KycRecord, _now_ms: &Option<u64>): bool {
    record.status != KYC_DENIED &&
        record.status != KYC_EXPIRED
}

fun time_valid(record: &KycRecord, now_ms: &Option<u64>): bool {
    if (record.expires_ms == 0) {
        true
    } else if (now_ms.is_some()) {
        *now_ms.borrow() <= record.expires_ms
    } else {
        false
    }
}
