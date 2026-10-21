// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {MADToken} from "../src/MADToken.sol";

/// @dev Test fixture only; the actual launch factory is external to this project.
contract FactoryFixture {
    function deploy(bytes32 salt) external returns (MADToken) {
        return new MADToken{salt: salt}();
    }
}

contract MADTokenLaunchTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    function test_Create2FactoryReceivesEntireSupplyInsteadOfItsCaller() public {
        FactoryFixture factory = new FactoryFixture();
        bytes32 salt = keccak256("MAD factory deployment test");
        bytes32 initCodeHash = keccak256(type(MADToken).creationCode);
        address predicted =
            address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, initCodeHash)))));
        address caller = makeAddr("factory caller");

        vm.prank(caller);
        MADToken token = factory.deploy(salt);

        assertEq(address(token), predicted);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(caller), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertGt(address(token).code.length, 0);
        assertLe(address(token).code.length, 24_576);
    }

    /// @dev Checks the token legs of launch and trading; this is not an AMM simulation.
    function test_LaunchDistributionClaimsAndTradingTransfersAreExact() public {
        FactoryFixture factory = new FactoryFixture();
        MADToken token = factory.deploy(keccak256("MAD token flow test"));
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("pool manager");
        address requester = makeAddr("requester");
        address claimant = makeAddr("claimant");
        address trader = makeAddr("trader");
        uint256 swarmShare = SUPPLY / 10;
        uint256 poolShare = SUPPLY * 8 / 10;
        uint256 remainder = SUPPLY - swarmShare - poolShare;

        vm.startPrank(address(factory));
        assertTrue(token.transfer(distributor, swarmShare));
        assertTrue(token.transfer(poolManager, poolShare));
        assertTrue(token.transfer(requester, remainder));
        vm.stopPrank();
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.balanceOf(distributor), swarmShare);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.balanceOf(requester), remainder);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarmShare));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), swarmShare);

        uint256 bought = 123_456e18;
        vm.prank(poolManager);
        assertTrue(token.transfer(trader, bought));
        assertEq(token.balanceOf(trader), bought);
        assertEq(token.balanceOf(poolManager), poolShare - bought);
        vm.prank(trader);
        assertTrue(token.transfer(poolManager, bought));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(poolManager), poolShare);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(claimant) + token.balanceOf(poolManager) + token.balanceOf(requester), SUPPLY);
    }
}
