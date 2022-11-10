// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "./TestHelper.sol";

contract LiquidityBinPairTest is TestHelper {
    ILBPair _LBPairImplementation;

    function setUp() public {
        token6D = new ERC20MockDecimals(6);
        token18D = new ERC20MockDecimals(18);

        factory = new LBFactory(DEV, 8e14);
        _LBPairImplementation = new LBPair(factory);
        factory.setLBPairImplementation(address(_LBPairImplementation));
        setDefaultFactoryPresets(DEFAULT_BIN_STEP);
        addAllAssetsToQuoteWhitelist(factory);
        router = new LBRouter(ILBFactory(DEV), IJoeFactory(DEV), IWAVAX(DEV));

        pair = createLBPairDefaultFees(token6D, token18D);
    }

    function testPendingFeesNotIncreasingReverts() public {
        uint256[] memory _ids = new uint256[](2);
        _ids[0] = uint256(ID_ONE);
        _ids[1] = uint256(ID_ONE) - 1;
        vm.expectRevert(LBPair__OnlyStrictlyIncreasingId.selector);
        pair.pendingFees(DEV, _ids);
    }

    function testMintWrongLengthsReverts() public {
        uint256[] memory _ids;
        uint256[] memory _distributionX;
        uint256[] memory _distributionY;
        uint256 _numberBins = 0;
        _ids = new uint256[](_numberBins);
        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);

        vm.expectRevert(LBPair__WrongLengths.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);
        _numberBins = 2;
        _ids = new uint256[](_numberBins);
        _distributionX = new uint256[](_numberBins - 1);
        _distributionY = new uint256[](_numberBins);
        vm.expectRevert(LBPair__WrongLengths.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);
        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins - 1);
        vm.expectRevert(LBPair__WrongLengths.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);
    }

    function testBurnWrongLengthsReverts() public {
        uint256[] memory ids;
        uint256[] memory amounts;
        uint256 _numberBins = 0;
        ids = new uint256[](_numberBins);
        amounts = new uint256[](_numberBins);

        vm.expectRevert(LBPair__WrongLengths.selector);
        pair.burn(ids, amounts, DEV);
        _numberBins = 2;
        ids = new uint256[](_numberBins);
        amounts = new uint256[](_numberBins - 1);
        vm.expectRevert(LBPair__WrongLengths.selector);
        pair.burn(ids, amounts, DEV);
    }

    function testDistributionOverflowReverts() public {
        uint256 amount = 10e18;
        token6D.mint(address(pair), amount);
        token18D.mint(address(pair), amount);
        uint256[] memory _ids;
        uint256[] memory _distributionX;
        uint256[] memory _distributionY;
        uint256 _numberBins = 1;
        _ids = new uint256[](_numberBins);
        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);

        _ids[0] = ID_ONE;

        _distributionY = new uint256[](_numberBins);
        _distributionX[0] = Constants.PRECISION + 1;
        vm.expectRevert(LBPair__DistributionsOverflow.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);

        _distributionX[0] = 0;
        _distributionY[0] = Constants.PRECISION + 1;
        vm.expectRevert(LBPair__DistributionsOverflow.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);

        _numberBins = 2;
        _ids = new uint256[](_numberBins);
        _ids[0] = ID_ONE;
        _ids[1] = ID_ONE + 1;
        _distributionX = new uint256[](_numberBins);
        _distributionY = new uint256[](_numberBins);
        _distributionX[0] = Constants.PRECISION / 2;
        _distributionX[1] = Constants.PRECISION / 2 + 1;
        vm.expectRevert(LBPair__DistributionsOverflow.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);

        _ids[0] = ID_ONE - 1;
        _ids[1] = ID_ONE;
        _distributionX[0] = 0;
        _distributionX[1] = 0;
        _distributionY[0] = Constants.PRECISION / 2;
        _distributionY[1] = Constants.PRECISION / 2 + 1;
        vm.expectRevert(LBPair__DistributionsOverflow.selector);
        pair.mint(_ids, _distributionX, _distributionY, DEV);
    }

    function testInsufficientLiquidityBurnedReverts() public {
        uint256 _numberBins = 2;
        uint256[] memory _ids;
        uint256[] memory _amounts;
        _ids = new uint256[](_numberBins);
        _amounts = new uint256[](_numberBins);
        _ids[0] = ID_ONE;
        _ids[1] = ID_ONE + 1;
        _amounts[0] = 0;
        _amounts[1] = 0;
        vm.expectRevert(abi.encodeWithSelector(LBPair__InsufficientLiquidityBurned.selector, _ids[0]));
        pair.burn(_ids, _amounts, DEV);
    }

    function testCollectingFeesOnlyFeeRecipient() public {
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(LBPair__OnlyFeeRecipient.selector, DEV, ALICE));
        pair.collectProtocolFees();
    }

    function testDeployingPairWithoutChecks() public {
        uint24 _activeId = ID_ONE;
        uint16 _sampleLifetime;
        bytes32 _packedFeeParameters;
        vm.startPrank(address(factory));

        vm.expectRevert(LBPair__AddressZero.selector);
        _LBPairImplementation.initialize(IERC20(address(0)), token18D, _activeId, _sampleLifetime, _packedFeeParameters);
        vm.expectRevert(LBPair__AddressZero.selector);
        _LBPairImplementation.initialize(token18D, IERC20(address(0)), _activeId, _sampleLifetime, _packedFeeParameters);

        _LBPairImplementation.initialize(token18D, token6D, _activeId, _sampleLifetime, _packedFeeParameters);
        vm.expectRevert(LBPair__AlreadyInitialized.selector);
        _LBPairImplementation.initialize(token18D, token6D, _activeId, _sampleLifetime, _packedFeeParameters);
    }
}
