// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

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
        bool isOpen;
    }

    function getPreset(uint256 _bp) internal pure returns (FactoryPreset memory preset) {
        if (_bp == 1) {
            preset.binStep = 1;
            preset.baseFactor = 20_000;
            preset.filterPeriod = 10;
            preset.decayPeriod = 120;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 2_000_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 100_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        } else if (_bp == 2) {
            preset.binStep = 2;
            preset.baseFactor = 15_000;
            preset.filterPeriod = 10;
            preset.decayPeriod = 120;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 500_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 250_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        } else if (_bp == 5) {
            preset.binStep = 5;
            preset.baseFactor = 8_000;
            preset.filterPeriod = 30;
            preset.decayPeriod = 600;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 120_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 300_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        } else if (_bp == 10) {
            preset.binStep = 10;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 30;
            preset.decayPeriod = 600;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 40_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 350_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        } else if (_bp == 15) {
            preset.binStep = 15;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 30;
            preset.decayPeriod = 600;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 30_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 350_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        } else if (_bp == 20) {
            preset.binStep = 20;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 30;
            preset.decayPeriod = 600;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 20_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 350_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        } else if (_bp == 25) {
            preset.binStep = 25;
            preset.baseFactor = 10_000;
            preset.filterPeriod = 30;
            preset.decayPeriod = 600;
            preset.reductionFactor = 5_000;
            preset.variableFeeControl = 15_000;
            preset.protocolShare = 0;
            preset.maxVolatilityAccumulated = 350_000;
            preset.sampleLifetime = 120;
            preset.isOpen = false;
        }
    }

    function getPresetList() internal pure returns (uint256[] memory presetList) {
        presetList = new uint256[](7);
        presetList[0] = 1;
        presetList[1] = 2;
        presetList[2] = 5;
        presetList[3] = 10;
        presetList[4] = 15;
        presetList[5] = 20;
        presetList[6] = 25;
    }
}
