// SPDX-License-Identifier: MIT

import "./Encoder.sol";
import "./Decoder.sol";

pragma solidity 0.8.7;

library Samples {
    using Encoder for uint256;
    using Decoder for bytes32;

    ///  [ cumulativeBinCrossed | cumulativeVolatilityAccumulated | cumulativeId | timestamp | initialized ]
    ///  [        uint87        |    uint64    |    uint64    |   uint40  |    bool1    ]
    /// MSB                                                                            LSB

    uint256 private constant _OFFSET_INITIALIZED = 0;
    uint256 private constant _MASK_INITIALIZED = 1;

    uint256 private constant _OFFSET_TIMESTAMP = 1;
    uint256 private constant _MASK_TIMESTAMP = type(uint40).max;

    uint256 private constant _OFFSET_CUMULATIVE_ID = 41;
    uint256 private constant _MASK_CUMULATIVE_ID = type(uint64).max;

    uint256 private constant _OFFSET_CUMULATIVE_VolatilityAccumulated = 105;
    uint256 private constant _MASK_CUMULATIVE_VolatilityAccumulated = type(uint64).max;

    uint256 private constant _OFFSET_CUMULATIVE_BIN_CROSSED = 169;
    uint256 private constant _MASK_CUMULATIVE_BIN_CROSSED = 0x7fffffffffffffffffffff;

    /// @notice Function to update a sample
    /// @param _lastSample The latest sample of the oracle
    /// @param _activeId The active index of the pair during the latest swap
    /// @param _volatilityAccumulated The volatility accumulated of the pair during the latest swap
    /// @param _binCrossed The bin crossed during the latest swap
    /// @return packedSample The packed sample as bytes32
    function update(
        bytes32 _lastSample,
        uint256 _activeId,
        uint256 _volatilityAccumulated,
        uint256 _binCrossed
    ) internal view returns (bytes32 packedSample) {
        unchecked {
            uint256 _currentTimestamp = block.timestamp;
            uint256 _deltaTime = _currentTimestamp - timestamp(_lastSample);
            uint256 _cumulativeId = cumulativeId(_lastSample) + _activeId * _deltaTime;
            uint256 _cumulativeVolatilityAccumulated = cumulativeVolatilityAccumulated(_lastSample) + _volatilityAccumulated * _deltaTime;
            uint256 _cumulativeBinCrossed = cumulativeBinCrossed(_lastSample) + _binCrossed * _deltaTime;

            return pack(_cumulativeBinCrossed, _cumulativeVolatilityAccumulated, _cumulativeId, _currentTimestamp, 1);
        }
    }

    /// @notice Function to pack cumulative values
    /// @param _cumulativeBinCrossed The cumulative bin crossed
    /// @param _cumulativeVolatilityAccumulated The cumulative volatility accumulated
    /// @param _cumulativeId The cumulative index
    /// @param _timestamp The timestamp
    /// @param _initialized The initialized value
    /// @return packedSample The packed sample as bytes32
    function pack(
        uint256 _cumulativeBinCrossed,
        uint256 _cumulativeVolatilityAccumulated,
        uint256 _cumulativeId,
        uint256 _timestamp,
        uint256 _initialized
    ) internal pure returns (bytes32 packedSample) {
        return
            _cumulativeBinCrossed.encode(_MASK_CUMULATIVE_BIN_CROSSED, _OFFSET_CUMULATIVE_BIN_CROSSED) |
            _cumulativeVolatilityAccumulated.encode(_MASK_CUMULATIVE_VolatilityAccumulated, _OFFSET_CUMULATIVE_VolatilityAccumulated) |
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

    /// @notice View function to return the cumulative volatility accumulated value
    /// @param _packedSample The packed sample
    /// @return The cumulative volatility accumulated value
    function cumulativeVolatilityAccumulated(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_CUMULATIVE_VolatilityAccumulated, _OFFSET_CUMULATIVE_VolatilityAccumulated);
    }

    /// @notice View function to return the cumulative bin crossed value
    /// @param _packedSample The packed sample
    /// @return The cumulative bin crossed value
    function cumulativeBinCrossed(bytes32 _packedSample) internal pure returns (uint256) {
        return _packedSample.decode(_MASK_CUMULATIVE_BIN_CROSSED, _OFFSET_CUMULATIVE_BIN_CROSSED);
    }
}
