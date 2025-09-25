// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct EventLog {
    // The topics of the log, including the signature, if any.
    bytes32[] topics;
    // The raw data of the log.
    bytes data;
    // The address of the log's emitter.
    address emitter;
}

struct EventFilter {
    // The address of the contract to filter logs from.
    address contractAddress;
    // The topics to filter logs by.
    string signature;
}

abstract contract Trap {
    EventLog[] private eventLogs;

    function collect() external view virtual returns (bytes memory);

    function shouldRespond(
        bytes[] calldata data
    ) external pure virtual returns (bool, bytes memory);

    function eventLogFilters() public view virtual returns (EventFilter[] memory) {
        EventFilter[] memory filters = new EventFilter[](0);
        return filters;
    }

    function version() public pure returns (string memory) {
        return "2.0";
    }

    function setEventLogs(EventLog[] calldata logs) public {
        EventLog[] storage storageArray = eventLogs;
        // Clear existing logs
        delete eventLogs;
        // Set new logs
        for (uint256 i = 0; i < logs.length; i++) {
            storageArray.push(EventLog({
                emitter: logs[i].emitter,
                topics: logs[i].topics,
                data: logs[i].data
            }));
        }
    }

    function getEventLogs() public view returns (EventLog[] memory) {
        EventLog[] storage storageArray = eventLogs;
        EventLog[] memory logs = new EventLog[](storageArray.length);
        for (uint256 i = 0; i < storageArray.length; i++) {
            logs[i] = EventLog({
                emitter: storageArray[i].emitter,
                topics: storageArray[i].topics,
                data: storageArray[i].data
            });
        }
        return logs;
    }
}