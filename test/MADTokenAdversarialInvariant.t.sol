// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Drives MAD with valid and invalid calls in random order. Every invalid call must revert with
/// the exact ERC-6093 error and leave balances, allowances and supply untouched; every valid call must
/// move exactly what the independent model says. Rejections are caught so `fail_on_revert` stays meaningful.
contract MADAdversarialHandler is Test {
    uint256 public constant SUPPLY = 1_000_000_000 * 10 ** 18;
    uint256 public constant ACTORS = 5;

    MADToken public immutable token;
    address[ACTORS] public actors;
    /// @dev Never approved by anyone and never funded: a caller the code has no reason to trust.
    address public immutable outsider;

    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public accepted;
    uint256 public rejected;
    uint256 public unexpectedOutcomes;

    constructor() {
        token = new MADToken();
        for (uint256 i; i < ACTORS; ++i) {
            actors[i] = makeAddr(string.concat("actor ", vm.toString(i)));
        }
        outsider = makeAddr("outsider");
        // Spread the supply unevenly so that small and whole-balance moves both occur.
        uint256 remaining = SUPPLY;
        for (uint256 i; i < ACTORS - 1; ++i) {
            uint256 share = remaining / 2;
            assertTrue(token.transfer(actors[i], share));
            expectedBalance[actors[i]] = share;
            remaining -= share;
        }
        assertTrue(token.transfer(actors[ACTORS - 1], remaining));
        expectedBalance[actors[ACTORS - 1]] = remaining;
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % ACTORS];
    }

    function _fingerprint() private view returns (bytes32 h) {
        h = keccak256(abi.encode(token.totalSupply(), token.balanceOf(outsider), token.balanceOf(address(0))));
        for (uint256 i; i < ACTORS; ++i) {
            h = keccak256(abi.encode(h, token.balanceOf(actors[i]), token.allowance(actors[i], outsider)));
            for (uint256 j; j < ACTORS; ++j) {
                h = keccak256(abi.encode(h, token.allowance(actors[i], actors[j])));
            }
        }
    }

    function _expectRejected(bytes memory call, address caller, bytes memory expectedError) private {
        bytes32 before = _fingerprint();
        vm.prank(caller);
        (bool ok, bytes memory ret) = address(token).call(call);
        if (ok || keccak256(ret) != keccak256(expectedError) || _fingerprint() != before) {
            ++unexpectedOutcomes;
        }
        ++rejected;
    }

    // ---------------------------------------------------------------- valid calls

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ++accepted;
    }

    function transferWholeBalance(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        ++accepted;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        ++accepted;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 maximum = allowed < expectedBalance[from] ? allowed : expectedBalance[from];
        uint256 amount = bound(rawAmount, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) expectedAllowance[from][spender] -= amount;
        ++accepted;
    }

    // ---------------------------------------------------------------- invalid calls

    function transferMoreThanBalance(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, balance + 1, type(uint256).max);
        _expectRejected(
            abi.encodeCall(token.transfer, (_actor(toSeed), amount)),
            from,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferToZeroAddress(uint256 fromSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        _expectRejected(
            abi.encodeCall(token.transfer, (address(0), amount)),
            from,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _expectRejected(
            abi.encodeCall(token.approve, (address(0), amount)),
            _actor(ownerSeed),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    function transferFromBeyondAllowance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount)
        external
    {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        if (allowed == type(uint256).max) return;
        uint256 amount = bound(rawAmount, allowed + 1, type(uint256).max);
        _expectRejected(
            abi.encodeCall(token.transferFrom, (from, _actor(toSeed), amount)),
            spender,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
    }

    function transferFromBeyondBalance(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 rawAmount)
        external
    {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        if (allowed <= balance) return;
        uint256 amount = bound(rawAmount, balance + 1, allowed);
        _expectRejected(
            abi.encodeCall(token.transferFrom, (from, _actor(toSeed), amount)),
            spender,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function transferFromToZeroAddress(uint256 fromSeed, uint256 spenderSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        address spender = _actor(spenderSeed);
        uint256 allowed = expectedAllowance[from][spender];
        uint256 maximum = allowed < expectedBalance[from] ? allowed : expectedBalance[from];
        uint256 amount = bound(rawAmount, 0, maximum);
        _expectRejected(
            abi.encodeCall(token.transferFrom, (from, address(0), amount)),
            spender,
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function outsiderSpendsWithoutApproval(uint256 fromSeed, uint256 rawAmount) external {
        address from = _actor(fromSeed);
        uint256 amount = bound(rawAmount, 1, type(uint256).max);
        _expectRejected(
            abi.encodeCall(token.transferFrom, (from, outsider, amount)),
            outsider,
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, outsider, 0, amount)
        );
    }

    function sumOfBalances() external view returns (uint256 sum) {
        for (uint256 i; i < ACTORS; ++i) {
            sum += token.balanceOf(actors[i]);
        }
    }
}

contract MADTokenAdversarialInvariantTest is Test {
    MADToken private token;
    MADAdversarialHandler private handler;

    function setUp() public {
        handler = new MADAdversarialHandler();
        token = handler.token();
        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = MADAdversarialHandler.transfer.selector;
        selectors[1] = MADAdversarialHandler.transferWholeBalance.selector;
        selectors[2] = MADAdversarialHandler.approve.selector;
        selectors[3] = MADAdversarialHandler.transferFrom.selector;
        selectors[4] = MADAdversarialHandler.transferMoreThanBalance.selector;
        selectors[5] = MADAdversarialHandler.transferToZeroAddress.selector;
        selectors[6] = MADAdversarialHandler.approveZeroSpender.selector;
        selectors[7] = MADAdversarialHandler.transferFromBeyondAllowance.selector;
        selectors[8] = MADAdversarialHandler.transferFromBeyondBalance.selector;
        selectors[9] = MADAdversarialHandler.transferFromToZeroAddress.selector;
        selectors[10] = MADAdversarialHandler.outsiderSpendsWithoutApproval.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_SupplyIsFixedAndFullyHeldByActors() public view {
        assertEq(token.totalSupply(), handler.SUPPLY(), "supply changed");
        assertEq(handler.sumOfBalances(), handler.SUPPLY(), "supply leaked outside the actors");
        assertEq(token.balanceOf(handler.outsider()), 0, "outsider received tokens");
        assertEq(token.balanceOf(address(0)), 0, "zero address holds tokens");
        assertEq(token.balanceOf(address(token)), 0, "token holds itself");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_BalancesAndAllowancesMatchModel() public view {
        for (uint256 i; i < handler.ACTORS(); ++i) {
            address holder = handler.actors(i);
            assertEq(token.balanceOf(holder), handler.expectedBalance(holder), "balance diverged from model");
            assertLe(token.balanceOf(holder), handler.SUPPLY(), "balance above supply");
            assertEq(token.allowance(holder, handler.outsider()), 0, "outsider gained an allowance");
            for (uint256 j; j < handler.ACTORS(); ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(holder, spender),
                    handler.expectedAllowance(holder, spender),
                    "allowance diverged from model"
                );
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 100
    function invariant_RejectedCallsRevertExactlyAndChangeNothing() public view {
        assertEq(handler.unexpectedOutcomes(), 0, "an invalid call succeeded, reverted wrongly, or changed state");
    }

    /// @dev Guards against a vacuous run: the sequence must have exercised the token.
    function afterInvariant() public view {
        assertGt(handler.accepted() + handler.rejected(), 0, "handler made no calls");
    }
}
