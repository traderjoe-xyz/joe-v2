// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./Samples.sol";
import "./Buffer.sol";

error Oracle__AlreadyInitialized(uint256 _index);
error Oracle__LookUpTimestampTooRecent(uint256 _maxTimestamp, uint256 _lookUpTimestamp);
error Oracle__LookUpTimestampTooOld(uint256 _minTimestamp, uint256 _lookUpTimestamp);

library Oracle {
    using Samples for bytes32;
    using Buffer for uint256;

    struct Sample {
        uint256 timestamp;
        uint256 cumulativeId;
        uint256 cumulativeAccumulator;
        uint256 cumulativeBinCrossed;
    }

    /// @dev This is the keccak-256 hash of "oracle" subtracted by 1
    uint256 private constant _ORACLE_SLOT = 0x89cbf5af14e0328a3cd3a734f92c3832d729d431da79b7873a62cbeebd37beb5;

    /// @notice Function to update a sample
    /// @param _size The size of the oracle (last ids can be empty)
    /// @param _sampleLifetime The lifetime of a sample, it accumulates information for up to this timestamp
    /// @param _lastTimestamp The timestamp of the creation of the oracle's latest sample
    /// @param _lastIndex The index of the oracle's latest sample
    /// @param _activeId The active index of the pair during the latest swap
    /// @param _accumulator The accumulator of the pair during the latest swap
    /// @param _binCrossed The bin crossed during the latest swap
    /// @return updatedIndex The oracle updated index, it is either the same as before, or the next one
    function update(
        uint256 _size,
        uint256 _sampleLifetime,
        uint256 _lastTimestamp,
        uint256 _lastIndex,
        uint256 _activeId,
        uint256 _accumulator,
        uint256 _binCrossed
    ) external returns (uint256 updatedIndex) {
        bytes32 _updatedPackedSample = get(_lastIndex).update(_activeId, _accumulator, _binCrossed);

        updatedIndex = block.timestamp - _lastTimestamp >= _sampleLifetime ? _lastIndex.addMod(1, _size) : _lastIndex;

        set(updatedIndex, _updatedPackedSample);
    }

    /// @notice Initialize the sample
    /// @dev The index of the sample needs to be empty
    /// @param _index The index to initialize
    function initialize(uint256 _index) external {
        bytes32 _packedSample = get(_index);
        if (_packedSample != 0) revert Oracle__AlreadyInitialized(_index);

        set(_index, bytes32(uint256(1)));
    }

    /// @notice Return the sample at index `_index` as Sample
    /// @param _index The index to return
    /// @return The sample at index `_index`
    function getSample(uint256 _index) internal view returns (Sample memory) {
        return decodeSample(get(_index));
    }

    /// @notice Decodes the sample
    /// @param _packedSample The sample as bytes32
    /// @return The decoded sample
    function decodeSample(bytes32 _packedSample) internal pure returns (Sample memory) {
        return
            Sample({
                timestamp: _packedSample.timestamp(),
                cumulativeId: _packedSample.cumulativeId(),
                cumulativeAccumulator: _packedSample.cumulativeAccumulator(),
                cumulativeBinCrossed: _packedSample.cumulativeBinCrossed()
            });
    }

    /// @notice Return the sample at index `_index` as bytes32
    /// @param _index The index to return
    /// @return packedSample The packed sample at index `_index`
    function get(uint256 _index) private view returns (bytes32 packedSample) {
        assembly {
            packedSample := sload(add(_ORACLE_SLOT, _index))
        }
    }

    /// @notice Sets the sample at index `_index`
    /// @dev Warning it uses a sstore.
    /// @param _index The index of the sample to set
    /// @param _packedSample The sample values as bytes32
    function set(uint256 _index, bytes32 _packedSample) private {
        assembly {
            sstore(add(_ORACLE_SLOT, _index), _packedSample)
        }
    }

    /// @notice Binary search on oracle samples and return the 2 samples (as bytes32) that surrounds the `lookUpTimestamp`
    /// @param _index The index
    /// @param _lookUpTimestamp The looked up timestamp
    /// @param _activeSize The size of the oracle (without empty data)
    /// @return prev The last sample with a timestamp lower than the lookUpTimestamp
    /// @return next The first sample with a timestamp greater than the lookUpTimestamp
    function binarySearch(
        uint256 _index,
        uint256 _lookUpTimestamp,
        uint256 _activeSize
    ) internal view returns (bytes32 prev, bytes32 next) {
        unchecked {
            uint256 _low;
            uint256 _high = _activeSize - 1;

            uint256 _middle;

            bytes32 _sample;
            uint256 _sampleTimestamp;
            while (_high >= _low) {
                _middle = (_low + _high) / 2;
                _sample = get(_middle.addMod(_index, _activeSize));
                _sampleTimestamp = _sample.timestamp();
                if (_sampleTimestamp < _lookUpTimestamp) {
                    _low = _middle + 1;
                } else if (_sampleTimestamp > _lookUpTimestamp || _sampleTimestamp == 0) {
                    _high = _middle - 1;
                } else {
                    return (_sample, _sample);
                }
            }

            if (_sampleTimestamp < _lookUpTimestamp) {
                next = get(_middle.addMod(1, _activeSize));
                if (next.timestamp() < _sampleTimestamp)
                    // This edge case should be handled by the contract that calls this function
                    revert Oracle__LookUpTimestampTooRecent(_sampleTimestamp, _lookUpTimestamp);
                return (_sample, next);
            } else {
                prev = get(_middle.subMod(1, _activeSize));
                if (prev.timestamp() > _sampleTimestamp)
                    revert Oracle__LookUpTimestampTooOld(_sampleTimestamp, _lookUpTimestamp);
                return (prev, _sample);
            }
        }
    }
}
