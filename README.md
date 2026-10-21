# Mutually Assured Destruction (MAD)

A fixed-supply ERC-20 for the MAD custom-token launch.

| Parameter | Value |
| --- | --- |
| Contract | `src/MADToken.sol:MADToken` |
| Name | `Mutually Assured Destruction` |
| Symbol | `MAD` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Initial recipient | Immediate constructor caller (`msg.sender`) |
| Admin / owner | None |
| Application contracts | None |

## Behavior and assumptions

The name is branding: the brief specifies no destruction, burn, tax, or other
custom transfer mechanism. MAD therefore uses the unmodified OpenZeppelin
ERC-20 implementation with a single constructor mint. `INITIAL_SUPPLY` is the
named constant for that issuance. The deployed contract has no callable mint,
burn, pause, blacklist, seizure, ownership, initialization, or upgrade function.
Supply remains constant after deployment.

Transfers deliver the full requested amount and return `true`; invalid
operations revert with OpenZeppelin's ERC-6093 custom errors. Zero-value and
self-transfers are supported. Transfers to the zero address and approvals to
the zero spender revert. Holders can authorize spending through `approve` and
`transferFrom`; finite allowances decrease as they are spent, while the maximum
`uint256` allowance stays unchanged. `approve` overwrites the prior allowance.
Explicit approvals emit `Approval`; delegated spending emits `Transfer` and
does not emit an allowance-update `Approval` event in this library version.

There are no external calls or receiver callbacks in the token's constructor,
transfers, or approvals. Sending tokens to a contract does not check whether
it can return them. There is no recovery mechanism for misdirected tokens or
forced Ether; ordinary Ether transfers revert.

## Build and test

Solidity is pinned to **0.8.26**, with optimization enabled (200 runs), the Cancun
EVM target, and `bytecode_hash = "none"`. Foundry needs that compiler available.
All Solidity dependencies and their licenses are ordinary files under `lib/`;
no package installation, git submodule, RPC, wallet, or network connection is
needed to build or test once Foundry and the pinned compiler are installed.
FFI and filesystem permissions are disabled.

```sh
forge build
FOUNDRY_FUZZ_SEED=0x92b2c2b028686b6fa4a753aa0c1e8ce494cf6eff3bcad05b164696a2b3cafc17 forge test
forge fmt --check
```

Tests use deterministic local fixtures and do not read or change environment
variables. The seed above configures Foundry itself. Coverage includes exact
metadata and constructor issuance, the mint event, transfer and approval events,
balance and allowance boundaries, zero values, self-transfers, unlimited
approvals, atomic failure rollback, unauthorized spending, absent privileged
entry points, and receipt by contracts that reject callbacks. Fuzz tests cover
valid and invalid transfer ranges. Stateful invariant testing runs 128 sequences
of 64 actions, checking supply, every holder balance, and every allowance against
an independent accounting model. Standard fuzz tests run 256 cases each.

The factory fixture exercises real CREATE2 deployment and checks that the
factory receives the supply rather than its caller. A transfer-flow test covers
the 10% distributor share, 80% pool share, remaining 10%, claims, and both trading
transfer directions. It checks the token legs only, not Uniswap pricing or
settlement. The network's separate protected launch harness performs the full
factory/pool integration checks; it is not bundled in this project.

## Deployment parameters and responsibilities

Deploy the compiled `MADToken` creation bytecode with **no constructor arguments
and no Ether**. The constructor needs no external contracts, owner address,
oracle, service, or post-deployment configuration. It emits one
`Transfer(address(0), deployer, 10^27)` event.

On the specified Ethereum launch (chain ID 1), the launch factory is the
constructor caller and receives all tokens. It is responsible for subsequent
distribution to the launch distributor, pool, and requester according to the
launch economics. The token does not allocate or reserve any supply itself.
Pool configuration, the FWA pairing, fees, and distribution recipients belong
to that external launch process and are not token constructor parameters.
`launch.json` is produced by the later manifest step, not this project.

Deploying directly from an EOA instead gives that EOA the entire supply.
Do not deploy through an intermediary that cannot distribute its tokens.
The deployer should confirm the artifact/compiler settings, initial recipient,
metadata, initial mint event, and exact supply before distribution, and verify
the deployed source on the chain explorer. This repository performs no live
deployment or transaction broadcast.

## After launch

No owner setters, keepers, or administrative maintenance are required or
available. The launch operator handles distribution and pool operations.
Holders control their transfers and approvals; integrations should request only
needed allowances and revoke unused approvals. When replacing a nonzero
allowance, account for a spender consuming the old allowance before the
replacement transaction; first revoke it and confirm the transaction.

No administrator can recover lost tokens, freeze an account, reverse a transfer,
or patch the deployed contract. A release requires the network's independent
adversarial review and integration verification. Local testing and source review
are not a separate security audit. Slither and Mythril were not run.

Dependency versions, provenance, licenses, and file hashes are recorded in
[`DEPENDENCIES.md`](DEPENDENCIES.md) and [`lib/SHA256SUMS`](lib/SHA256SUMS).
