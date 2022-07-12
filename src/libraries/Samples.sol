// SPDX-License-Identifier: MIT

import "./Encoder.sol";
import "./Decoder.sol";

pragma solidity 0.8.9;

library Samples {
    using Encoder for uint256;
    using Decoder for bytes32;

    ///  [ cumulativeBinCrossed | cumulativeAccumulator | cumulativeId | timestamp | initialized ]
    ///  [        uint51        |        uint104        |    uint60    |   uint40  |    bool1    ]
    /// MSB                                                                                     LSB

    uint256 private constant _OFFSET_INITIALIZED = 0;
    uint256 private constant _MASK_INITIALIZED = 1;

    uint256 private constant _OFFSET_TIMESTAMP = 1;
    uint256 private constant _MASK_TIMESTAMP = (1 << 40) - 1;

    uint256 private constant _OFFSET_CUMULATIVE_ID = 41;
    uint256 private constant _MASK_CUMULATIVE_ID = (1 << 60) - 1;

    uint256 private constant _OFFSET_CUMULATIVE_ACCUMULATOR = 101;
    uint256 private constant _MASK_CUMULATIVE_ACCUMULATOR = (1 << 104) - 1;

    uint256 private constant _OFFSET_CUMULATIVE_BIN_CROSSED = 205;
    uint256 private constant _MASK_CUMULATIVE_BIN_CROSSED = (1 << 51) - 1;

    function update(
        bytes32 _lastSample,
        uint256 _activeId,
        uint256 _accumulator,
        uint256 _binCrossed
    ) internal view returns (bytes32) {
        uint256 _currentTimestamp = block.timestamp;
        uint256 _deltaTime = _currentTimestamp - timestamp(_lastSample);
        uint256 _cumulativeId = cumulativeId(_lastSample) + _activeId * _deltaTime;
        uint256 _cumulativeAccumulator = cumulativeAccumulator(_lastSample) + _accumulator * _deltaTime;
        uint256 _cumulativeBinCrossed = cumulativeBinCrossed(_lastSample) + _binCrossed * _deltaTime;

        return pack(_cumulativeBinCrossed, _cumulativeAccumulator, _cumulativeId, _currentTimestamp, 1);
    }

    function pack(
        uint256 _cumulativeBinCrossed,
        uint256 _cumulativeAccumulator,
        uint256 _cumulativeId,
        uint256 _timestamp,
        uint256 _initialized
    ) internal pure returns (bytes32) {
        return
            _cumulativeBinCrossed.encode(_MASK_CUMULATIVE_BIN_CROSSED, _OFFSET_CUMULATIVE_BIN_CROSSED) |
            _cumulativeAccumulator.encode(_MASK_CUMULATIVE_ACCUMULATOR, _OFFSET_CUMULATIVE_ACCUMULATOR) |
            _cumulativeId.encode(_MASK_CUMULATIVE_ID, _OFFSET_CUMULATIVE_ID) |
            _timestamp.encode(_MASK_TIMESTAMP, _OFFSET_TIMESTAMP) |
            _initialized.encode(_MASK_INITIALIZED, _OFFSET_INITIALIZED);
    }

    function initialized(bytes32 _sample) internal pure returns (uint256) {
        return _sample.decode(_MASK_INITIALIZED, _OFFSET_INITIALIZED);
    }

    function timestamp(bytes32 _sample) internal pure returns (uint256) {
        return _sample.decode(_MASK_TIMESTAMP, _OFFSET_TIMESTAMP);
    }

    function cumulativeId(bytes32 _sample) internal pure returns (uint256) {
        return _sample.decode(_MASK_CUMULATIVE_ID, _OFFSET_CUMULATIVE_ID);
    }

    function cumulativeAccumulator(bytes32 _sample) internal pure returns (uint256) {
        return _sample.decode(_MASK_CUMULATIVE_ACCUMULATOR, _OFFSET_CUMULATIVE_ACCUMULATOR);
    }

    function cumulativeBinCrossed(bytes32 _sample) internal pure returns (uint256) {
        return _sample.decode(_MASK_CUMULATIVE_BIN_CROSSED, _OFFSET_CUMULATIVE_BIN_CROSSED);
    }
}
