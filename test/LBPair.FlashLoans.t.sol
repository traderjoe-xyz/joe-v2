// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.10;

import "./TestHelper.sol";

contract LiquidityBinPairFlashLoansTest is TestHelper {
    FlashBorrower private borrower;

    event CalldataTransmitted();

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        ILBPair _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        addAllAssetsToQuoteWhitelist(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);

        borrower = new FlashBorrower(pair);
    }

    function testFlashloan() public {
        (uint256[] memory _ids, , , ) = addLiquidity(100e18, ID_ONE, 9, 5);
        uint256 amountXBorrowed = 10e18;
        uint256 amountYBorrowed = 10e18;

        // Paying for fees
        token6D.mint(address(borrower), 1e18);
        token18D.mint(address(borrower), 1e18);

        vm.expectEmit(false, false, false, false);
        emit CalldataTransmitted();

        borrower.flashBorrow(amountXBorrowed, amountYBorrowed);

        (uint256 feesForDevX, uint256 feesForDevY) = pair.pendingFees(DEV, _ids);
        assertGt(feesForDevX, 0, "DEV should have fees on token X");
        assertGt(feesForDevY, 0, "DEV should have fees on token Y");
    }

    function testFailFlashloanMoreThanReserves() public {
        uint256 amountXBorrowed = 150e18;

        token6D.mint(address(borrower), 1e18);

        borrower.flashBorrow(amountXBorrowed, 0);
    }

    function testFailFlashlaonWithReentrancy() public {
        uint256 amountXBorrowed = 150e18;

        token6D.mint(address(borrower), 1e18);

        borrower.flashBorrowWithReentrancy(amountXBorrowed, 0);
    }
}
