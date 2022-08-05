// SPDX-License-Identifier: MIT

import "./Encoder.sol";
import "./Decoder.sol";

pragma solidity 0.8.7;

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

    /// @notice Function to update a sample
    /// @param _lastSample The latest sample of the oracle
    /// @param _activeId The active index of the pair during the latest swap
    /// @param _accumulator The accumulator of the pair during the latest swap
    /// @param _binCrossed The bin crossed during the latest swap
    /// @return packedSample The packed sample as bytes32
    function update(
        bytes32 _lastSample,
        uint256 _activeId,
        uint256 _accumulator,
        uint256 _binCrossed
    ) internal view returns (bytes32 packedSample) {
        unchecked {
            uint256 _currentTimestamp = block.timestamp;
            uint256 _deltaTime = _currentTimestamp - timestamp(_lastSample);
            uint256 _cumulativeId = cumulativeId(_lastSample) + _activeId * _deltaTime;
            uint256 _cumulativeAccumulator = cumulativeAccumulator(_lastSample) + _accumulator * _deltaTime;
            uint256 _cumulativeBinCrossed = cumulativeBinCrossed(_lastSample) + _binCrossed * _deltaTime;

            return pack(_cumulativeBinCrossed, _cumulativeAccumulator, _cumulativeId, _currentTimestamp, 1);
        }
    }

    /// @notice Function to pack cumulative values
    /// @param _cumulativeBinCrossed The cumulative bin crossed
    /// @param _cumulativeAccumulator The cumulative accumulator
    /// @param _cumulativeId The cumulative index
    /// @param _timestamp The timestamp
    /// @param _initialized The initialized value
    /// @return packedSample The packed sample as bytes32
    function pack(
        uint256 _cumulativeBinCrossed,
        uint256 _cumulativeAccumulator,
        uint256 _cumulativeId,
        uint256 _timestamp,
        uint256 _initialized
    ) internal pure returns (bytes32 packedSample) {
        return
            _cumulativeBinCrossed.encode(_MASK_CUMULATIVE_BIN_CROSSED, _OFFSET_CUMULATIVE_BIN_CROSSED) |
            _cumulativeAccumulator.encode(_MASK_CUMULATIVE_ACCUMULATOR, _OFFSET_CUMULATIVE_ACCUMULATOR) |
            _cumulativeId.encode(_MASK_CUMULATIVE_ID, _OFFSET_CUMULATIVE_ID) |
            _timestamp.encode(_MASK_TIMESTAMP, _OFFSET_TIMESTAMP) |
            _initialized.encode(_MASK_INITIALIZED, _OFFSET_INITIALIZED);
    }

    /// @notice View function to return the initialized value
    /// @param _packedSample The packed sample
    /// @return The initialized value
    function initialized(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_INITIALIZED, _OFFSET_INITIALIZED);
    }

    /// @notice View function to return the timestamp value
    /// @param _packedSample The packed sample
    /// @return The timestamp value
    function timestamp(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_TIMESTAMP, _OFFSET_TIMESTAMP);
    }

    /// @notice View function to return the cumulative id value
    /// @param _packedSample The packed sample
    /// @return The cumulative id value
    function cumulativeId(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_CUMULATIVE_ID, _OFFSET_CUMULATIVE_ID);
    }

    /// @notice View function to return the cumulative accumulator value
    /// @param _packedSample The packed sample
    /// @return The cumulative accumulator value
    function cumulativeAccumulator(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_CUMULATIVE_ACCUMULATOR, _OFFSET_CUMULATIVE_ACCUMULATOR);
    }

    /// @notice View function to return the cumulative bin crossed value
    /// @param _packedSample The packed sample
    /// @return The cumulative bin crossed value
    function cumulativeBinCrossed(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_CUMULATIVE_BIN_CROSSED, _OFFSET_CUMULATIVE_BIN_CROSSED);
    }
}
