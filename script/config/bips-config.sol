// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

library BipsConfig {
    struct FactoryPreset {
        uint16 binStep;
        uint16 baseFactor;
        uint16 filterPeriod;
        uint16 decayPeriod;
        uint16 reductionFactor;
        uint24 variableFeeControl;
        uint16 protocolShare;
        uint24 maxVolatilityAccumulated;
        uint16 sampleLifetime;
    }

    function getPreset(uint256 _bp) internal pure returns (FactoryPreset memory preset) {
        if (_bp == 1) {
            preset.binStep = 1;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 1;
            preset.decayPeriod = 300;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 80_000;
            preset.protocolShare = 2_000;
            preset.maxVolatilityAccumulated = 500_000;
            preset.sampleLifetime = 120;
        } else if (_bp == 2) {
            preset.binStep = 2;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 1;
            preset.decayPeriod = 300;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 70_000;
            preset.protocolShare = 2_000;
            preset.maxVolatilityAccumulated = 500_000;
            preset.sampleLifetime = 120;
        } else if (_bp == 5) {
            preset.binStep = 5;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 1;
            preset.decayPeriod = 300;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 60_000;
            preset.protocolShare = 2_000;
            preset.maxVolatilityAccumulated = 500_000;
            preset.sampleLifetime = 120;
        } else if (_bp == 10) {
            preset.binStep = 10;
            preset.baseFactor = 5_000;
            preset.filterPeriod = 1;
            preset.decayPeriod = 300;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 40_000;
            preset.protocolShare = 2_000;
            preset.maxVolatilityAccumulated = 400_000;
            preset.sampleLifetime = 120;
        } else if (_bp == 15) {
            preset.binStep = 15;
            preset.baseFactor = 5_000;
            preset.filterPeriod = 1;
            preset.decayPeriod = 300;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 35_000;
            preset.protocolShare = 2_000;
            preset.maxVolatilityAccumulated = 350_000;
            preset.sampleLifetime = 120;
        } else if (_bp == 20) {
            preset.binStep = 20;
            preset.baseFactor = 5_000;
            preset.filterPeriod = 1;
            preset.decayPeriod = 300;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 30_000;
            preset.protocolShare = 2_000;
            preset.maxVolatilityAccumulated = 350_000;
            preset.sampleLifetime = 120;
        }
    }

    function getPresetList() internal pure returns (uint256[] memory presetList) {
        presetList = new uint256[](6);
        presetList[0] = 1;
        presetList[1] = 2;
        presetList[2] = 5;
        presetList[3] = 10;
        presetList[4] = 15;
        presetList[5] = 20;
    }
}
