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

        router = new LBRouter(factory, IJoeFactory(JOE_V1_FACTORY_ADDRESS), IWAVAX(address(wavax)));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testAddLiquidityNoSlippage() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (int256[] memory _deltaIds, , , uint256 amountXIn) = addLiquidityFromRouter(
            _amountYIn,
            _startId,
            _numberBins,
            _gap,
            0
        );

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(DEV, ids[i]);
        }

        vm.startPrank(DEV);
        pair.setApprovalForAll(address(router), true);

        router.removeLiquidity(token6D, token18D, amountXIn - 2, _amountYIn, ids, amounts, DEV, block.timestamp);
        vm.stopPrank();

        assertEq(token6D.balanceOf(DEV), amountXIn);
        assertEq(token18D.balanceOf(DEV), _amountYIn);
    }

    function testAddLiquidityAVAX() public {
        pair = createLBPairDefaultFees(token6D, wavax);

        uint256 _amountAVAXIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (
            int256[] memory _deltaIds,
            uint256[] memory _distributionToken,
            uint256[] memory _distributionAVAX,
            uint256 amountTokenIn
        ) = spreadLiquidityForRouter(_amountAVAXIn, _startId, _numberBins, _gap);

        token6D.mint(ALICE, amountTokenIn);
        vm.deal(ALICE, _amountAVAXIn);

        vm.startPrank(ALICE);
        token6D.approve(address(router), amountTokenIn);
        router.addLiquidityAVAX{value: _amountAVAXIn}(
            token6D,
            amountTokenIn,
            0,
            ID_ONE,
            0,
            _deltaIds,
            _distributionToken,
            _distributionAVAX,
            ALICE,
            block.timestamp
        );

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(ALICE, ids[i]);
        }

        pair.setApprovalForAll(address(router), true);

        uint256 AVAXBalanceBefore = address(ALICE).balance;
        uint256 tokenBalanceBefore = token6D.balanceOf(ALICE);
        router.removeLiquidityAVAX(
            token6D,
            amountTokenIn - tokenBalanceBefore,
            _amountAVAXIn,
            ids,
            amounts,
            ALICE,
            block.timestamp
        );
        assertEq(token6D.balanceOf(ALICE), amountTokenIn);
        assertEq(address(ALICE).balance - AVAXBalanceBefore, _amountAVAXIn);

        vm.stopPrank();
    }

    function testAddLiquidityTaxToken() public {
        taxToken = new ERC20WithTransferTax();
        pair = createLBPairDefaultFees(taxToken, wavax);

        uint256 _amountAVAXIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        (
            int256[] memory _deltaIds,
            uint256[] memory _distributionToken,
            uint256[] memory _distributionAVAX,
            uint256 amountTokenIn
        ) = spreadLiquidityForRouter(_amountAVAXIn, _startId, _numberBins, _gap);

        taxToken.mint(ALICE, amountTokenIn);
        vm.deal(ALICE, _amountAVAXIn);

        vm.startPrank(ALICE);
        taxToken.approve(address(router), amountTokenIn);
        router.addLiquidityAVAX{value: _amountAVAXIn}(
            taxToken,
            amountTokenIn,
            4_999,
            ID_ONE,
            0,
            _deltaIds,
            _distributionToken,
            _distributionAVAX,
            ALICE,
            block.timestamp
        );

        uint256[] memory amounts = new uint256[](_numberBins);
        uint256[] memory ids = new uint256[](_numberBins);
        for (uint256 i; i < _numberBins; i++) {
            ids[i] = uint256(int256(uint256(ID_ONE)) + _deltaIds[i]);
            amounts[i] = pair.balanceOf(ALICE, ids[i]);
        }

        pair.setApprovalForAll(address(router), true);

        vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
        router.removeLiquidityAVAX(
            taxToken,
            amountTokenIn / 2 - 1,
            _amountAVAXIn,
            ids,
            amounts,
            ALICE,
            block.timestamp
        );

        router.removeLiquidity(
            taxToken,
            wavax,
            amountTokenIn / 2 - 1,
            _amountAVAXIn,
            ids,
            amounts,
            ALICE,
            block.timestamp
        );

        assertEq(taxToken.balanceOf(ALICE), amountTokenIn / 4 + 1);
        assertEq(wavax.balanceOf(ALICE), _amountAVAXIn);

        vm.stopPrank();
    }

    function testFailForIdSlippageCaught() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        addLiquidityFromRouter(_amountYIn, _startId, _numberBins, _gap, 0);

        uint256 amountXOutForSwap = 30e18;
        uint256 amountYInForSwap = router.getSwapIn(pair, amountXOutForSwap, false);
        token18D.mint(address(pair), amountYInForSwap);
        pair.swap(true, ALICE);

        addLiquidityFromRouter(_amountYIn, _startId, _numberBins, _gap, 0);
    }

    function testFailForSlippageCaught() public {
        uint256 _amountYIn = 100e18;
        uint24 _startId = ID_ONE;
        uint24 _numberBins = 9;
        uint24 _gap = 2;

        addLiquidityFromRouter(_amountYIn, _startId, _numberBins, _gap, 0);

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

        router.addLiquidity(
            token6D,
            token18D,
            amountXIn,
            _amountYIn,
            10_000,
            ID_ONE,
            3,
            _deltaIds,
            _distributionX,
            _distributionY,
            DEV,
            block.timestamp
        );
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

        router.addLiquidity(
            token6D,
            token18D,
            amountXIn,
            _amountYIn,
            0,
            ID_ONE,
            3,
            _wrongLengthDeltaIds,
            _distributionX,
            _distributionY,
            DEV,
            block.timestamp
        );
    }

    receive() external payable {}
}
