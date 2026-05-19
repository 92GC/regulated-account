module regulated_account::validation;

use std::string::String;
use regulated_account::constants;

const EInvalidVectorSize: u64 = 27;
const EMemoRequired: u64 = 10;
const EInvalidAmount: u64 = 33;

public(package) fun assert_positive_amount(amount: u64) {
    assert!(amount > 0, EInvalidAmount);
}

public(package) fun assert_external_ref_hash(bytes: &vector<u8>) {
    assert_vector_size(bytes, constants::max_external_ref_hash_bytes());
}

public(package) fun assert_memo_required(memo_required: bool, memo: &vector<u8>) {
    assert_vector_size(memo, constants::max_memo_bytes());
    assert!(!memo_required || memo.length() > 0, EMemoRequired);
}

public(package) fun assert_metadata_fields(
    symbol: &String,
    name: &String,
    description: &String,
    icon_url: &String,
) {
    assert_string_size(symbol, constants::max_symbol_bytes());
    assert_string_size(name, constants::max_name_bytes());
    assert_string_size(description, constants::max_description_bytes());
    assert_string_size(icon_url, constants::max_icon_url_bytes());
}

public(package) fun assert_vector_size(bytes: &vector<u8>, max: u64) {
    assert!(bytes.length() <= max, EInvalidVectorSize);
}

fun assert_string_size(value: &String, max: u64) {
    assert!(value.as_bytes().length() <= max, EInvalidVectorSize);
}
