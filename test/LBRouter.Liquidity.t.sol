// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.9;

import "./TestHelper.sol";

contract LiquidityBinRouterTest is TestHelper {
    event AVAXreceived();

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);
        wavax = new WAVAX();

        factory = new LBFactory(DEV);
        new LBFactoryHelper(factory);
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testAddLiquidityNoSlippage() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountXIn) = addLiquidityFromRouter(
            token6D,
            token18D,
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            DEFAULT_BIN_STEP
        );

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(DEV, ids[i]);
        }

        pair.setApprovalForAll(address(router), true);

        router.removeLiquidity(
            token6D,
            token18D,
            DEFAULT_BIN_STEP,
            amountXIn - 10,
            _amountYIn,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        assertEq(token6D.balanceOf(DEV), amountXIn);
        assertEq(token18D.balanceOf(DEV), _amountYIn);
    }

    function testAddLiquidityAVAX() public {
        pair = createLBPairDefaultFees(token6D, wavax);

        uint256 _amountAVAXIn = 100e18;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountTokenIn) = addLiquidityFromRouter(
            token6D,
            ERC20MockDecimals(address(wavax)),
            _amountAVAXIn,
            ID_ONE,
            9,
            _gap,
            DEFAULT_BIN_STEP
        );

        uint256[] memory amounts = new uint256[](9);
        uint256[] memory ids = new uint256[](9);
        for (uint256 i; i < 9; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(DEV, ids[i]);
        }

        pair.setApprovalForAll(address(router), true);

        uint256 AVAXBalanceBefore = address(DEV).balance;
        {
            router.removeLiquidityAVAX(
                token6D,
                DEFAULT_BIN_STEP,
                amountTokenIn - 10,
                _amountAVAXIn,
                ids,
                amounts,
                DEV,
                block.timestamp
            );
        }
        assertEq(token6D.balanceOf(DEV), amountTokenIn);
        assertEq(address(DEV).balance - AVAXBalanceBefore, _amountAVAXIn);
    }

    function testAddLiquidityTaxToken() public {
        taxToken = new ERC20WithTransferTax();
        pair = createLBPairDefaultFees(taxToken, wavax);

        uint256 _amountAVAXIn = 100e18;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountTokenIn) = addLiquidityFromRouter(
            ERC20MockDecimals(address(taxToken)),
            ERC20MockDecimals(address(wavax)),
            _amountAVAXIn,
            ID_ONE,
            9,
            _gap,
            DEFAULT_BIN_STEP
        );

        uint256[] memory amounts = new uint256[](9);
        uint256[] memory ids = new uint256[](9);
        for (uint256 i; i < 9; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(DEV, ids[i]);
        }

        pair.setApprovalForAll(address(router), true);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        router.removeLiquidityAVAX(
            taxToken,
            DEFAULT_BIN_STEP,
            amountTokenIn / 2 - 10,
            _amountAVAXIn,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        router.removeLiquidity(
            taxToken,
            wavax,
            DEFAULT_BIN_STEP,
            amountTokenIn / 2 - 10,
            _amountAVAXIn,
            ids,
            amounts,
            DEV,
            block.timestamp
        );

        assertEq(taxToken.balanceOf(DEV), amountTokenIn / 4 + 1);
        assertEq(wavax.balanceOf(DEV), _amountAVAXIn);
    }

    function testFailAddLiquidityBlacklistedPair() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        ILBPair pairBlacklisted = factory.getLBPair(token6D, token18D, DEFAULT_BIN_STEP);
        factory.setLBPairBlacklist(pairBlacklisted, true);

        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);
    }

    function testFailForIdSlippageCaught() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);

        uint256 amountXOutForSwap = 30e18;
        uint256 amountYInForSwap = router.getSwapIn(pair, amountXOutForSwap, false);
        token18D.mint(address(pair), amountYInForSwap);
        pair.swap(true, ALICE);

        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);
    }

    function testFailForSlippageCaught() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        addLiquidityFromRouter(token6D, token18D, _amountYIn, _startId, _numberBins, _gap, DEFAULT_BIN_STEP);

        (
            int256[] memory _deltaIds,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amountXIn
        ) = spreadLiquidityForRouter(_amountYIn, _startId, _numberBins, _gap);

        uint256 amountXOutForSwap = 30e18;
        uint256 amountYInForSwap = router.getSwapIn(pair, amountXOutForSwap, false);
        token18D.mint(address(pair), amountYInForSwap);
        pair.swap(true, ALICE);

        token6D.mint(DEV, amountXIn);
        token6D.approve(address(router), amountXIn);
        token18D.mint(DEV, _amountYIn);
        token18D.approve(address(router), _amountYIn);

        ILBRouter.LiquidityParameters memory _liquidityParameters = ILBRouter.LiquidityParameters(
            token6D,
            token18D,
            DEFAULT_BIN_STEP,
            amountXIn,
            _amountYIn,
            0,
            0,
            ID_ONE,
            0,
            _deltaIds,
            _distributionX,
            _distributionY,
            DEV,
            block.timestamp
        );

        router.addLiquidity(_liquidityParameters);
    }

    function testFailForLengthsMismatch() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (
            int256[] memory _deltaIds,
            uint256[] memory _distributionX,
            uint256[] memory _distributionY,
            uint256 amountXIn
        ) = spreadLiquidityForRouter(_amountYIn, _startId, _numberBins, _gap);

        int256[] memory _wrongLengthDeltaIds = new int256[](_numberBins - 1);
        for (uint256 i; i < _numberBins - 1; i++) {
            _wrongLengthDeltaIds[i] = _deltaIds[i];
        }

        token6D.mint(DEV, amountXIn);
        token6D.approve(address(router), amountXIn);
        token18D.mint(DEV, _amountYIn);
        token18D.approve(address(router), _amountYIn);

        ILBRouter.LiquidityParameters memory _liquidityParameters = ILBRouter.LiquidityParameters(
            token6D,
            token18D,
            DEFAULT_BIN_STEP,
            amountXIn,
            _amountYIn,
            0,
            0,
            ID_ONE,
            0,
            _wrongLengthDeltaIds,
            _distributionX,
            _distributionY,
            DEV,
            block.timestamp
        );

        router.addLiquidity(_liquidityParameters);
    }

    receive() external payable {}
}
