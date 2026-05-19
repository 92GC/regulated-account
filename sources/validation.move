module regulated_account::validation;

use std::string::String;

const MAX_MEMO_BYTES: u64 = 256;
const MAX_EXTERNAL_REF_HASH_BYTES: u64 = 64;
const MAX_SYMBOL_BYTES: u64 = 16;
const MAX_NAME_BYTES: u64 = 64;
const MAX_DESCRIPTION_BYTES: u64 = 512;
const MAX_ICON_URL_BYTES: u64 = 256;

const EInvalidVectorSize: u64 = 27;
const EMemoRequired: u64 = 10;
const EInvalidAmount: u64 = 33;

public(package) fun assert_positive_amount(amount: u64) {
    assert!(amount > 0, EInvalidAmount);
}

public(package) fun assert_external_ref_hash(bytes: &vector<u8>) {
    assert_vector_size(bytes, MAX_EXTERNAL_REF_HASH_BYTES);
}

public(package) fun assert_memo_required(memo_required: bool, memo: &vector<u8>) {
    assert_vector_size(memo, MAX_MEMO_BYTES);
    assert!(!memo_required || memo.length() > 0, EMemoRequired);
}

public(package) fun assert_metadata_fields(
    symbol: &String,
    name: &String,
    description: &String,
    icon_url: &String,
) {
    assert_string_size(symbol, MAX_SYMBOL_BYTES);
    assert_string_size(name, MAX_NAME_BYTES);
    assert_string_size(description, MAX_DESCRIPTION_BYTES);
    assert_string_size(icon_url, MAX_ICON_URL_BYTES);
}

public(package) fun assert_vector_size(bytes: &vector<u8>, max: u64) {
    assert!(bytes.length() <= max, EInvalidVectorSize);
}

fun assert_string_size(value: &String, max: u64) {
    assert!(value.as_bytes().length() <= max, EInvalidVectorSize);
}
