// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinPairFlashLoansTest is TestHelper {
    FlashBorrower private borrower;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);
        router = new LBRouter(ILBFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);

        addLiquidity(100e18, ID_ONE, 9, 5);

        borrower = new FlashBorrower(IERC3156FlashLender(address(pair)));
    }

    function testFlashloan() public {}
}
