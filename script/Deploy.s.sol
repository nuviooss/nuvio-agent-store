// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/NuvioAgentStore.sol";

/// @notice Deploy NuvioAgentStore. Broadcasts with the key provided by forge.
/// @dev On mainnet the deployment is executed via the Binance Agentic Wallet
/// (baw contract-call preview/execute) using the creation bytecode printed by
/// `forge inspect NuvioAgentStore bytecode`; this script is for local/anvil
/// gas measurement and testnet rehearsal only.
contract Deploy is Script {
    address constant AGENT_ID = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address constant USDT = 0x55d398326f99059fF775485246999027B3197955;

    function run() external returns (NuvioAgentStore store) {
        vm.broadcast();
        store = new NuvioAgentStore(AGENT_ID, USDT, msg.sender);
    }
}
