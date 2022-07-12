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

    // @dev This is the keccak-256 hash of "oracle" subtracted by 1
    uint256 private constant _ORACLE_SLOT = 0x89cbf5af14e0328a3cd3a734f92c3832d729d431da79b7873a62cbeebd37beb5;

    function update(
        uint256 _size,
        uint256 _sampleLifetime,
        uint256 _lastTimestamp,
        uint256 _lastIndex,
        uint256 _activeId,
        uint256 _accumulator,
        uint256 _binCrossed
    ) external returns (uint256 updatedIndex) {
        bytes32 _updatedSample = get(_lastIndex).update(_activeId, _accumulator, _binCrossed);

        updatedIndex = block.timestamp - _lastTimestamp >= _sampleLifetime ? _lastIndex.addMod(1, _size) : _lastIndex;

        set(updatedIndex, _updatedSample);
    }

    function initialize(uint256 _index) external {
        bytes32 _sample = get(_index);
        if (_sample != 0) revert Oracle__AlreadyInitialized(_index);

        set(_index, bytes32(uint256(1)));
    }

    function getSample(uint256 _index) internal view returns (Sample memory) {
        return decodeSample(get(_index));
    }

    function decodeSample(bytes32 _sample) internal pure returns (Sample memory) {
        return
            Sample({
                timestamp: _sample.timestamp(),
                cumulativeId: _sample.cumulativeId(),
                cumulativeAccumulator: _sample.cumulativeAccumulator(),
                cumulativeBinCrossed: _sample.cumulativeBinCrossed()
            });
    }

    function get(uint256 _index) private view returns (bytes32 sample) {
        assembly {
            sample := sload(add(_ORACLE_SLOT, _index))
        }
    }

    function set(uint256 _index, bytes32 _sample) private {
        assembly {
            sstore(add(_ORACLE_SLOT, _index), _sample)
        }
    }

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
