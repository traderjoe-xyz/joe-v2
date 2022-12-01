// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";
import "../src/LBToken.sol";

contract LiquidityBinTokenTest is TestHelper, LBToken {
    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testInternalMintTo0AddressReverts() public {
        vm.expectRevert(LBToken__MintToAddress0.selector);
        _mint(address(0), 2**23, 1000);
    }

    function testInternalMint(uint256 mintAmount) public {
        uint256 binNumber = 2**23;
        uint256 totalSupplyBefore = totalSupply(binNumber);
        uint256 balanceBefore = balanceOf(ALICE, binNumber);
        vm.expectEmit(true, true, true, true);
        // The event we expect
        emit TransferSingle(msg.sender, address(0), ALICE, binNumber, mintAmount);
        _mint(ALICE, binNumber, mintAmount);

        assertEq(balanceOf(ALICE, binNumber), balanceBefore + mintAmount);
        assertEq(totalSupply(binNumber), totalSupplyBefore + mintAmount);
    }

    function testInternalBurnFrom0AddressReverts() public {
        vm.expectRevert(LBToken__BurnFromAddress0.selector);
        _burn(address(0), 2**23, 1000);
    }

    function testInternalExcessiveBurnAmountReverts(uint128 mintAmount, uint128 excessiveBurnAmount) public {
        vm.assume(excessiveBurnAmount > 0);
        uint256 burnAmount = uint256(mintAmount) + uint256(excessiveBurnAmount);
        uint256 binNumber = 2**23;
        _mint(ALICE, binNumber, mintAmount);
        vm.expectRevert(abi.encodeWithSelector(LBToken__BurnExceedsBalance.selector, ALICE, binNumber, burnAmount));
        _burn(ALICE, binNumber, burnAmount);
    }

    function testInternalBurn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0 && burnAmount > 0);
        vm.assume(mintAmount >= burnAmount);
        uint256 binNumber = 2**23;

        _mint(ALICE, binNumber, mintAmount);

        uint256 totalSupplyBefore = totalSupply(binNumber);
        uint256 balanceBefore = balanceOf(ALICE, binNumber);

        vm.expectEmit(true, true, true, true);
        // The event we expect
        emit TransferSingle(msg.sender, ALICE, address(0), binNumber, burnAmount);
        _burn(ALICE, binNumber, burnAmount);

        assertEq(balanceOf(ALICE, binNumber), balanceBefore - burnAmount);
        assertEq(totalSupply(binNumber), totalSupplyBefore - burnAmount);
    }

    function testInternalApproval() public {
        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(DEV, ALICE, true);
        _setApprovalForAll(DEV, ALICE, true);
        assertEq(_isApprovedForAll(DEV, ALICE), true);

        vm.expectEmit(true, true, true, true);
        emit ApprovalForAll(DEV, ALICE, false);
        _setApprovalForAll(DEV, ALICE, false);
        assertEq(_isApprovedForAll(DEV, ALICE), false);
    }

    function supportsInterface(bytes4 interfaceId) public view override(TestHelper, LBToken) returns (bool) {
        return interfaceId == type(ILBToken).interfaceId;
    }
}
