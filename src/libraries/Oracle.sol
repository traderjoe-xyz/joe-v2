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

    /// @notice Function to update a sample
    /// @param _oracle The oracle storage pointer
    /// @param _size The size of the oracle (last ids can be empty)
    /// @param _sampleLifetime The lifetime of a sample, it accumulates information for up to this timestamp
    /// @param _lastTimestamp The timestamp of the creation of the oracle's latest sample
    /// @param _lastIndex The index of the oracle's latest sample
    /// @param _activeId The active index of the pair during the latest swap
    /// @param _accumulator The accumulator of the pair during the latest swap
    /// @param _binCrossed The bin crossed during the latest swap
    /// @return updatedIndex The oracle updated index, it is either the same as before, or the next one
    function update(
        bytes32[65_536] storage _oracle,
        uint256 _size,
        uint256 _sampleLifetime,
        uint256 _lastTimestamp,
        uint256 _lastIndex,
        uint256 _activeId,
        uint256 _accumulator,
        uint256 _binCrossed
    ) internal returns (uint256 updatedIndex) {
        unchecked {
            bytes32 _updatedPackedSample = _oracle[_lastIndex].update(_activeId, _accumulator, _binCrossed);

            updatedIndex = block.timestamp - _lastTimestamp >= _sampleLifetime
                ? _lastIndex.addMod(1, _size)
                : _lastIndex;

            _oracle[updatedIndex] = _updatedPackedSample;
        }
    }

    /// @notice Initialize the sample
    /// @dev The index of the sample needs to be empty
    /// @param _oracle The oracle storage pointer
    /// @param _index The index to initialize
    function initialize(bytes32[65_536] storage _oracle, uint256 _index) internal {
        bytes32 _packedSample = _oracle[_index];
        if (_packedSample != 0) revert Oracle__AlreadyInitialized(_index);

        _oracle[_index] = bytes32(uint256(1));
    }

    /// @notice Return the sample at index `_index` as Sample
    /// @param _oracle The oracle storage pointer
    /// @param _index The index to return
    /// @return The sample at index `_index`
    function getSample(bytes32[65_536] storage _oracle, uint256 _index) internal view returns (Sample memory) {
        return decodeSample(_oracle[_index]);
    }

    /// @notice Binary search on oracle samples and return the 2 samples (as bytes32) that surrounds the `lookUpTimestamp`
    /// @param _oracle The oracle storage pointer
    /// @param _index The index
    /// @param _lookUpTimestamp The looked up timestamp
    /// @param _activeSize The size of the oracle (without empty data)
    /// @return prev The last sample with a timestamp lower than the lookUpTimestamp
    /// @return next The first sample with a timestamp greater than the lookUpTimestamp
    function binarySearch(
        bytes32[65_536] storage _oracle,
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
                _sample = _oracle[_middle.addMod(_index, _activeSize)];
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
                next = _oracle[_middle.addMod(1, _activeSize)];
                if (next.timestamp() < _sampleTimestamp)
                    // This edge case should be handled by the contract that calls this function
                    revert Oracle__LookUpTimestampTooRecent(_sampleTimestamp, _lookUpTimestamp);
                prev = _sample;
            } else {
                prev = _oracle[_middle.subMod(1, _activeSize)];
                if (prev.timestamp() > _sampleTimestamp)
                    revert Oracle__LookUpTimestampTooOld(_sampleTimestamp, _lookUpTimestamp);
                next = _sample;
            }
        }
    }

    /// @notice Decodes the sample
    /// @param _packedSample The sample as bytes32
    /// @return sample The decoded sample
    function decodeSample(bytes32 _packedSample) internal pure returns (Sample memory sample) {
        sample.timestamp = _packedSample.timestamp();
        sample.cumulativeId = _packedSample.cumulativeId();
        sample.cumulativeAccumulator = _packedSample.cumulativeAccumulator();
        sample.cumulativeBinCrossed = _packedSample.cumulativeBinCrossed();
    }
}
