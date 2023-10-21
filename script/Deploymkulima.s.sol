// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Mkulima} from "../src/mkulima.sol";
import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMkulima is Script {
    function run() external returns (Mkulima, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();

        (address priceFeed, uint256 deployerKey) = helperConfig
            .activeNetworkConfig();

        vm.startBroadcast(deployerKey);
        Mkulima mkulima = new Mkulima(priceFeed);
        vm.stopBroadcast();

        return (mkulima, helperConfig);
    }
}
