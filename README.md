# .Etc Name Service (HENS)
ETC Name Service (.Etc Name) brings decentralized name registration, reverse primary names, free subname distribution, and multi-coin / text / contenthash record management to Ethereum Classic Mainnet. No more hex addresses — payments, dApps and social identity become readable at a glance.  
https://etcname.com 

## Overview

HENS provides `.etc` names as NFTs (ERC-721). Names can:
- Resolve to an Ethereum Classic address (receive payments)
- Host a website via IPFS, IPNS, or Swarm contenthash
- Have unlimited free subdomains
- Store multi-coin addresses and text records (ENS-compatible resolver)
- Display as your wallet's identity (reverse resolution)

The contract is a single, non-upgradeable Solidity file (`NameNFT.sol`) that combines ERC-721 ownership, registration logic, and resolver functionality.

- **Solidity:** `^0.8.30`
- **License:** MIT

---

## Constants

All fee parameters are `constant`. There are no admin-settable fee variables, so there are also no admin caps.

| Constant | Value | Description |
|---|---|---|
| `ETC_NODE` | `0x2f1420...8162c9` | Namehash of the "etc" TLD |
| `MAX_LABEL_LENGTH` | 255 bytes | Maximum label byte length |
| `MIN_LABEL_LENGTH` | 1 byte | Minimum label byte length |
| `MIN_COMMITMENT_AGE` | 60 seconds | Minimum wait before reveal |
| `MAX_COMMITMENT_AGE` | 86400 seconds (24h) | Commitment expiration |
| `REGISTRATION_PERIOD` | 365 days | Duration of one registration |
| `GRACE_PERIOD` | 90 days | Post-expiry renewal window |
| `MAX_SUBDOMAIN_DEPTH` | 10 | Maximum nesting of subdomains |
| `COIN_TYPE_ETC` | 61 | SLIP-44 coin type for ETC |
| `FEE_LEN1` | 25 ETC | Fee for 1-byte labels |
| `FEE_LEN2` | 5 ETC | Fee for 2-byte labels |
| `FEE_LEN3` | 1 ETC | Fee for 3-byte labels |
| `FEE_LEN4` | 0.25 ETC | Fee for 4-byte labels |
| `DEFAULT_FEE` | 0.5 ETC | Fee for 5+ byte labels |
| `MAX_PREMIUM` | 100 ETC | Fixed starting anti-snipe premium |
| `PREMIUM_DECAY_PERIOD` | 21 days | Fixed premium decay window |

---

## Name Lifecycle

### 1. Registration (Commit-Reveal)

A two-step commit-reveal pattern prevents frontrunning:

1. **Commit** — Submit `keccak256(abi.encode(normalizedLabel, owner, secret))` on-chain. The commitment uses the *normalized* label bytes (ASCII lowercased), not the raw input.
2. **Wait** — At least 60 seconds (`MIN_COMMITMENT_AGE`).
3. **Reveal** — Submit the label, secret, and payment. The commitment must be no older than 24 hours (`MAX_COMMITMENT_AGE`).

The commitment is deleted after a successful reveal. An expired commitment (>24h) can be overwritten by a new `commit()`.

**Off-chain commitment computation:**
```javascript
// IMPORTANT: normalize the label the same way the contract does (lowercase ASCII)
const normalized = label.toLowerCase(); // for ASCII-only labels
const commitment = ethers.keccak256(
  ethers.AbiCoder.defaultAbiCoder().encode(
    ['bytes', 'address', 'bytes32'],
    [ethers.toUtf8Bytes(normalized), ownerAddress, secret]
  )
);
```

### 2. Active Period

- Registration lasts **365 days** from the time of reveal.
- The name is **active** while `block.timestamp <= expiresAt`.
- While active: transfers, resolver writes, and resolution all work.

### 3. Expiry + Grace Period

- After `expiresAt`, the name enters a **90-day grace period**.
- During grace: the name is **not active** — transfers are blocked, resolver reads return empty, resolver writes revert.
- During grace: **renewal is allowed** and extends from the original `expiresAt` (not from current time).
- Anyone can call `renew()` for any name (not restricted to the owner).

### 4. Full Expiration

- After `expiresAt + GRACE_PERIOD`, the name is fully expired.
- It can be re-registered by anyone through a new commit-reveal cycle.
- Re-registration increments the `epoch`, invalidating all existing subdomains.
- Re-registration increments `recordVersion`, clearing all resolver data.

### 5. Premium Pricing (Dutch Auction)

Immediately after a name fully expires (grace period ends), a premium is charged on top of the base fee. The premium starts at `MAX_PREMIUM` (fixed: 100 ETC) and decays linearly to 0 over `PREMIUM_DECAY_PERIOD` (fixed: 21 days).

```
premium = MAX_PREMIUM * (PREMIUM_DECAY_PERIOD - elapsed) / PREMIUM_DECAY_PERIOD
```

Where `elapsed` is seconds since `expiresAt + GRACE_PERIOD`. After the decay period, premium is 0. Like the base fee, this premium is **burned** (locked in the contract) — it is an anti-snipe cost, not revenue.

---

## Fee Structure

### Fixed Length-Based Schedule, and Burned

HENS keeps the — shorter labels cost more, to make squatting premium names expensive — but freezes it into `constant`s:

| Label length (UTF-8 bytes) | Fee |
|---|---|
| 1 | 25 ETC |
| 2 | 5 ETC |
| 3 | 1 ETC |
| 4 | 0.25 ETC |
| 5 or more | 0.05 ETC (`DEFAULT_FEE`) |

```
getFee(length):
  length == 1 → 25 ETC
  length == 2 → 5 ETC
  length == 3 → 1 ETC
  length == 4 → 0.25 ETC
  else        → 0.05 ETC
```

The fee is keyed on `bytes(label).length` (UTF-8 byte length, not character count) — e.g. a 4-byte emoji pays the 4-byte tier.

- **The schedule cannot change.** Every tier is a `constant`. There is no `setDefaultFee`, no `setLengthFees`. 

### Renewal Fee

Renewal costs the same length-based fee as registration. No premium is charged on renewal. 

---


## Subdomains

### Registration

- Parent owner calls `registerSubdomain(label, parentId)` or `registerSubdomainFor(label, parentId, to)`.
- Subdomains are **free** (no fee).
- Subdomains have **no independent expiry** — they are active as long as the parent chain is active.
- Maximum nesting depth: 10 levels below the top-level name.

### Epoch-Based Invalidation

Each name record has an `epoch` counter. When a subdomain is created, it stores `parentEpoch` — the parent's epoch at creation time. A subdomain is considered **stale** (inactive) if its `parentEpoch` does not match the parent's current `epoch`.

This happens when:
- The parent name expires and is re-registered (epoch increments).
- The parent owner reclaims the subdomain via `registerSubdomain()` (burns the old token, mints a new one with incremented epoch).

Stale subdomains:
- Return empty strings from resolver reads.
- Show `[Invalid]` in `tokenURI`.
- Cannot be transferred (blocked by `_isActive` check in `_beforeTokenTransfer`).

### Reclaim

The parent owner can always call `registerSubdomain()` with an existing subdomain label. This burns the old token (clearing the previous owner's holding), increments the epoch, and mints a fresh token to the parent owner. The previous owner's `primaryName` is cleared if it pointed to the reclaimed token.

**Note:** `isAvailable()` returns `false` for active subdomains, even though the parent owner can overwrite them. Parent owners should call `registerSubdomain()` directly — it will succeed for reclaim regardless of `isAvailable()` result.

---

## Record Versioning

Each token has a `recordVersion` counter. All resolver data (address, contenthash, multi-coin addresses, text records) is keyed by `(tokenId, recordVersion)`. When a name is re-registered after expiry, `recordVersion` is incremented, effectively clearing all previous resolver data without paying gas to delete storage.

---

## Resolution

### Forward Resolution

```
resolve(tokenId):
  if name is not active → return address(0)
  if explicit address is set → return that address
  else → return ownerOf(tokenId)
```

The fallback to `ownerOf` means a freshly registered name resolves to its owner by default.

### Reverse Resolution

Users set a **primary name** via `setPrimaryName(tokenId)`. The caller must be the token owner or the address that the token resolves to.

```
reverseResolve(addr):
  if primaryName[addr] is 0, or name is not active, or resolve(tokenId) != addr → return ""
  else → return "label.etc" (or "sub.label.etc" etc.)
```

Setting `primaryName` to `tokenId = 0` clears the primary name.


### Multi-Coin Addresses

`setAddrForCoin(tokenId, coinType, addr)` stores addresses for any SLIP-44 coin type. For coin type 61 (ETC), the `addr()` function first checks the explicit coin address, then falls back to `resolve()`.

### Text Records

Standard key-value text records via `setText` / `text`. Common keys: `avatar`, `url`, `description`, `com.twitter`, `com.github`, etc.

### Contenthash

`setContenthash` / `contenthash` for IPFS/Swarm/etc. content addressing. Used by the gateway (`*`) to serve websites. A name can instead point at a contract-hosted site through the `contentcontract` text record 

---


## Access Control

| Function | Access |
|---|---|
| `commit` | Anyone |
| `reveal` | Anyone (must match commitment owner) |
| `registerSubdomain` / `registerSubdomainFor` | Parent token owner only |
| `renew` | Anyone (for any name) |
| `setAddr`, `setContenthash`, `setAddrForCoin`, `setText` | Token owner only |
| `setPrimaryName` | Token owner or resolved address |

---

## Transfer Restrictions

The `_beforeTokenTransfer` hook blocks transfers of **inactive** tokens. A token is inactive when:
- Top-level name: `block.timestamp > expiresAt` (after expiry, including during grace period)
- Subdomain: parent epoch mismatch, or parent chain is inactive

Mint (`from == address(0)`) and burn (`to == address(0)`) are always allowed regardless of active status.

---

## Security Properties

### Reentrancy Protection

The following functions have the `nonReentrant` modifier:
- `reveal` — uses `_safeMint` which calls `onERC721Received` on contract recipients
- `registerSubdomain` / `registerSubdomainFor` — also uses `_safeMint`
- `renew` — sends ETC refund

### Refund Handling

`reveal` and `renew` refund excess ETC to `msg.sender` via `SafeTransferLib.safeTransferETH`. If the caller cannot receive ETC (e.g., a contract without a `receive` function), the transaction reverts.

### Frontrunning Protection

The commit-reveal scheme requires a 60-second minimum delay between commit and reveal, preventing miners/searchers from observing a reveal transaction and frontrunning it.

### Primary Name Cleanup

When a name is re-registered or a subdomain is reclaimed, if the previous owner's `primaryName` pointed to that token, it is deleted.

---



