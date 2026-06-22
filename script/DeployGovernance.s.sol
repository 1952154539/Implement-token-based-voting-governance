// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GovToken} from "../src/GovToken.sol";
import {Bank} from "../src/Bank.sol";
import {Gov} from "../src/Gov.sol";

contract DeployGovernance is Script {
    uint256 constant INITIAL_SUPPLY = 1_000_000;
    uint48 constant VOTING_DELAY = 1;
    uint32 constant VOTING_PERIOD = 50400; // ~1 week (assuming 12s blocks)
    uint256 constant PROPOSAL_THRESHOLD = 10_000 ether;
    uint256 constant QUORUM_NUMERATOR = 4; // 4%

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy GovToken
        GovToken token = new GovToken(INITIAL_SUPPLY);
        console.log("GovToken deployed at:", address(token));

        // 2. Deploy Bank
        Bank bank = new Bank();
        console.log("Bank deployed at:", address(bank));

        // 3. Deploy Gov
        Gov gov = new Gov(
            token,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD,
            QUORUM_NUMERATOR
        );
        console.log("Gov deployed at:", address(gov));

        // 4. Set Gov as Bank admin
        bank.setAdmin(address(gov));
        console.log("Bank admin set to Gov");

        // 5. Transfer token ownership to Gov (optional, for decentralized control)
        // token.transferOwnership(address(gov));
        // console.log("Token ownership transferred to Gov");

        vm.stopBroadcast();

        console.log("--- Deployment Summary ---");
        console.log("Token total supply:", INITIAL_SUPPLY, "tokens");
        console.log("Voting delay:", VOTING_DELAY, "blocks");
        console.log("Voting period:", VOTING_PERIOD, "blocks");
        console.log("Proposal threshold:", PROPOSAL_THRESHOLD / 1e18, "tokens");
        console.log("Quorum:", QUORUM_NUMERATOR, "%");
    }
}
