# Regulated Account Split Plan

This package should become a canonical core plus extension packages, not a fork
template. Forked implementations create different Move types, which breaks
wallet/indexer discovery. A real standard needs one canonical package ID whose
`Asset<T>`, `Account<T>`, receipts, and events are stable.

## Goal

Keep `regulated_account` as the boring, canonical Sui object/account standard:

- `Asset<T>`
- `Account<T>`
- holder and identity keys
- wallet discovery receipts
- standard transfer/mint/burn/freeze/clawback/pause events
- basic issuer caps
- stable getters for wallets, indexers, and typed extensions

Everything issuer-specific or legally domain-specific should move to typed
extension packages that bind to the core via `asset_id` and `account_id`.

## Current Split

- `regulated_account`: minimal issuer/user-facing facade for asset/account
  creation.
- `asset`: canonical `Asset<T>` state and asset-level policy internals.
- `account`: canonical `Account<T>` state and account-level balance/lock
  internals.
- `caps`: issuer/admin capability types.
- `authority`: holder authority and time hot-potato types.
- `metadata`: metadata registry and canonical receipt metadata.
- `receipt`: wallet-discovery receipt object.
- `ledger`: mint/burn/clawback and balance accounting.
- `transfer`: transfer execution paths.
- `compliance`: KYC, authorization, freeze/thaw, pause, and account policy
  administration.
- `kyc`: KYC record schema and status/time validity checks.
- `shareholders`: shareholder counters and minimum-positive-balance invariants.
- `fees`: transfer-fee config and arithmetic.
- `keys`, `events`, `policy_events`, `amount_math`: small canonical support
  modules.

This split intentionally moves `Asset<T>` and `Account<T>` out of the facade
before devnet so wallets, indexers, and extension packages key on clean
canonical type paths from the beginning.

## Keep In Core

- Asset/account creation with one-time witness.
- Public balance accounting.
- Address and package holders; address and external identities.
- Canonical `HolderAuthority<T>` and `Time` hot-potato constructors for
  holder-controlled calls.
- Witness/package authorization for package-held accounts used by wrappers,
  vaults, and DvP-style modules.
- Identity key field for beneficial-owner mapping.
- Basic allowlist/denylist/open mode, plus one-way compliance-mode locking.
- Mint, burn, transfer, freeze/thaw, pause/unpause, clawback.
- Registration/reassignment with reason hash.
- Locked balance for partial liens/pledges.
- Shareholder cap counters if identity remains in core.
- Minimum positive balance policy for dust prevention.
- Display scale for splits/rebases.
- Package-level `MetadataRegistry` plus canonical shared
  `AssetMetadata<Receipt<T>>` for receipt-type metadata discovery.
- Transfer fees for transfer-agent/KYC-provider economics.
- Receipt object for wallet discovery.
- No generic transfer-hook/request mechanism in core; built-in policy remains
  explicit in the transfer path.

## Move To Extensions

- Future alternate transfer lanes once canonical Sui primitives are stable enough
  to standardize against.
- Tax routing and venue-specific settlement fees.
- Bond terms: coupon, accrual, maturity, payment asset, redemption.
- Complex KYC/identity registries.
- Jurisdiction/investor-class eligibility checks.
- Restricted lots, if the core needs to be more minimal.
- Dividend, voting, record-date, and snapshot systems.
- Escrow, DVP, broker, wrapper, and exchange integration logic.

## Extension Pattern

Extensions should define typed objects:

```move
public struct BondTerms<phantom T> has key {
    id: UID,
    asset_id: ID,
    coupon_bps: u64,
    maturity_ms: u64,
}
```

Extension functions assert the object is attached to the core asset:

```move
assert!(terms.asset_id == regulated_account::asset::id(asset), EAssetMismatch);
```

Extensions can bind typed state to the core asset/account IDs, but they do not
participate in core transfer authorization through a generic hook mechanism.

## Open Design Questions

- Should core KYC remain as a simple default table, or should all KYC move to a
  registry/rule extension?
- Should restricted lots stay in core for equities, or become a Rule 144/vesting
  extension?
- Should future custody integrations need object-held accounts, or is package
  authority enough for v1 integrations?
- What shape should future alternate transfer lanes take once Sui's canonical
  primitives are available?

## Standardization Requirements

- Publish one canonical package ID.
- Freeze the public object/event schema.
- Provide conformance tests for issuers and extensions.
- Provide SDK helpers for account discovery and PTB construction.
- Provide indexer queries keyed by canonical `Asset<T>` and `Account<T>` types.
- Document issuer powers clearly: freeze, pause, clawback, burn, registration,
  KYC mutation, fee policy, minimum balance policy, and admin-action reason
  hashes.
