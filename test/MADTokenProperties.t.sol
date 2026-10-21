// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Deploys the token and performs its first distribution in one call, as a launch factory does
/// in one transaction.
contract OneTransactionLauncher {
    function launch(address[] calldata recipients, uint256[] calldata amounts) external returns (MADToken token) {
        token = new MADToken();
        for (uint256 i; i < recipients.length; ++i) {
            require(token.transfer(recipients[i], amounts[i]), "transfer returned false");
        }
    }
}

/// @dev Stateless properties at the arithmetic edges: round trips, idempotence, and unauthorized callers.
contract MADTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    MADToken private token;
    address private deployer;

    function setUp() public {
        deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new MADToken();
    }

    /// @dev Maps any seed to a nonzero address distinct from the deployer and the token, without discarding runs.
    function _addr(uint256 seed, string memory tag) private returns (address) {
        return makeAddr(string.concat(tag, vm.toString(seed)));
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_TransferRoundTripRestoresState(uint256 seed, uint256 amount) public {
        address other = _addr(seed, "other");
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(other, amount));
        vm.prank(other);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(other), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SplitTransfersEqualOneTransfer(uint256 seed, uint256 first, uint256 second) public {
        address a = _addr(seed, "a");
        address b = _addr(seed, "b");
        // The pair is sent twice, so it may total at most half the supply.
        first = bound(first, 0, SUPPLY / 2);
        second = bound(second, 0, SUPPLY / 2 - first);
        vm.startPrank(deployer);
        assertTrue(token.transfer(a, first));
        assertTrue(token.transfer(a, second));
        assertTrue(token.transfer(b, first + second));
        vm.stopPrank();
        assertEq(token.balanceOf(a), token.balanceOf(b));
        assertEq(token.balanceOf(deployer) + token.balanceOf(a) + token.balanceOf(b), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_SelfTransferIsANoOp(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, amount));
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_ApproveIsIdempotentAndOverwrites(uint256 seed, uint256 first, uint256 second) public {
        address spender = _addr(seed, "spender");
        vm.startPrank(deployer);
        assertTrue(token.approve(spender, first));
        assertTrue(token.approve(spender, first));
        assertEq(token.allowance(deployer, spender), first);
        assertTrue(token.approve(spender, second));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), second);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_UnlimitedAllowanceNeverDecreases(uint256 seed, uint256 a, uint256 b) public {
        address spender = _addr(seed, "spender");
        address to = _addr(seed, "to");
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        vm.prank(deployer);
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(deployer, to, a));
        assertTrue(token.transferFrom(deployer, to, b));
        vm.stopPrank();
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(to), a + b);
    }

    /// @dev An allowance of max - 1 is finite and must be decremented, unlike max.
    function test_AllowanceOneBelowMaxIsDecremented() public {
        address spender = makeAddr("spender");
        address to = makeAddr("to");
        vm.prank(deployer);
        token.approve(spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, to, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_EmptyAccountCannotSendAnyPositiveAmount(uint256 seed, uint256 amount) public {
        address empty = _addr(seed, "empty");
        amount = bound(amount, 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, empty, 0, amount));
        vm.prank(empty);
        token.transfer(deployer, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_StrangerCannotPullFromDeployer(uint256 seed, uint256 amount) public {
        address stranger = _addr(seed, "stranger");
        amount = bound(amount, 1, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(deployer, stranger, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(stranger), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_AllowanceIsCheckedBeforeBalance(uint256 seed, uint256 allowed, uint256 amount) public {
        address holder = _addr(seed, "holder");
        address spender = _addr(seed, "spender");
        vm.prank(deployer);
        token.transfer(holder, 1e18);
        allowed = bound(allowed, 0, 1e18 - 1);
        amount = bound(amount, 1e18 + 1, type(uint256).max);
        vm.prank(holder);
        token.approve(spender, allowed);
        // Both limits are exceeded; the allowance is reported and nothing moves.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount)
        );
        vm.prank(spender);
        token.transferFrom(holder, spender, amount);
        assertEq(token.allowance(holder, spender), allowed);
        assertEq(token.balanceOf(holder), 1e18);
    }

    function test_OneWeiMovesExactly() public {
        address to = makeAddr("to");
        vm.prank(deployer);
        assertTrue(token.transfer(to, 1));
        assertEq(token.balanceOf(to), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_SpendingFromZeroAddressReverts() public {
        address spender = makeAddr("spender");
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), spender, 1);
    }

    function test_ZeroAddressCannotTransferOrApprove() public {
        vm.startPrank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(deployer, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(deployer, 1);
        vm.stopPrank();
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EachDeploymentIsIndependentAndMintsOnce() public {
        vm.prank(deployer);
        MADToken second = new MADToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(second)), 0);
        assertEq(second.balanceOf(address(token)), 0);
    }

    /// forge-config: default.fuzz.runs = 500
    function testFuzz_DeployAndDistributeInOneCall(uint256 a, uint256 b) public {
        OneTransactionLauncher launcher = new OneTransactionLauncher();
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("distributor");
        recipients[1] = makeAddr("pool");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = a;
        amounts[1] = b;
        MADToken launched = launcher.launch(recipients, amounts);
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(recipients[0]), a);
        assertEq(launched.balanceOf(recipients[1]), b);
        assertEq(launched.balanceOf(address(launcher)), SUPPLY - a - b);
        assertEq(launched.balanceOf(address(this)), 0);
    }

    function test_DistributingMoreThanSupplyInOneCallRevertsWholeLaunch() public {
        OneTransactionLauncher launcher = new OneTransactionLauncher();
        address[] memory recipients = new address[](2);
        recipients[0] = makeAddr("distributor");
        recipients[1] = makeAddr("pool");
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = SUPPLY;
        amounts[1] = 1;
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(launcher), 0, 1));
        launcher.launch(recipients, amounts);
    }
}
