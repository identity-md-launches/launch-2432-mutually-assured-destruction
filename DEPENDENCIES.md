# Vendored dependencies

These source snapshots are included as ordinary files. They are not submodules
and require no network access during compilation. `lib/SHA256SUMS` records each
vendored file; verify the snapshot locally with `sha256sum -c lib/SHA256SUMS`.

## OpenZeppelin Contracts v5.4.0

- Upstream: https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.4.0
- Archive: https://codeload.github.com/OpenZeppelin/openzeppelin-contracts/tar.gz/refs/tags/v5.4.0
- Archive SHA-256: `b89829be48bc501051002191733268a93ef6e238a4bb65d8fd1cbdf3969050d1`
- Included: unmodified `ERC20.sol`, `IERC20.sol`, `IERC20Metadata.sol`,
  `Context.sol`, `draft-IERC6093.sol`, and `LICENSE`.
- Location: `lib/openzeppelin-contracts/`.
- License: MIT, preserved in `lib/openzeppelin-contracts/LICENSE`.
- Purpose: token implementation and its complete transitive imports.

## Forge Standard Library v1.9.7

- Upstream: https://github.com/foundry-rs/forge-std/tree/v1.9.7
- Archive: https://codeload.github.com/foundry-rs/forge-std/tar.gz/refs/tags/v1.9.7
- Archive SHA-256: `45157353ab49eab01d294565866731e599b32401757229689ee459aa26b7ee94`
- Included: unmodified `src/` and the two upstream license files.
- Location: `lib/forge-std/`.
- License: MIT or Apache-2.0; both license texts are preserved there.
- Purpose: test assertions, cheatcode interfaces, fuzz helpers, and invariants.
  No forge-std code is imported by the production token.
