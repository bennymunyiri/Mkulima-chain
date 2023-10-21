// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Mkulima} from "../../src/mkulima.sol";
import {Test, console} from "forge-std/Test.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployMkulima} from "../../script/Deploymkulima.s.sol";

contract MkulimaTest is Test {
    address public priceFeed;
    uint256 public deployerKey;

    HelperConfig helperConfig;
    Mkulima mkulima;

    uint256 public constant STARTING_KGS_TO_SELL = 50;
    uint256 public constant PRICE_OF_20KGS_IN_WEI = 3e18;
    address public FARMER = makeAddr("Player");

    function setUp() external {
        DeployMkulima deployer = new DeployMkulima();
        (mkulima, helperConfig) = deployer.run();
        (priceFeed, deployerKey) = helperConfig.activeNetworkConfig();
        if (block.chainid == 31337) {
            vm.deal(FARMER, STARTING_KGS_TO_SELL);
        }
    }

    function testIsFailsWhenLessKGThanRequired() public {
        vm.prank(FARMER);
        vm.expectRevert(Mkulima.Mkulima__NotEnoughKilosOfCheeries.selector);
        mkulima.ConvertRawCheeriesToProduct(0);
    }

    function testofOneEthonAnvil() public {
        uint256 expectedUsd = 2000e18;
        uint256 usdValue = mkulima.getUsdValueOfOneEth();
        // price of one eth
        uint256 usdFinal = (1e18 * usdValue);
        assertEq(usdFinal, expectedUsd);
    }

    function testConvertRawToProductWithNoRemainder() public {
        vm.prank(FARMER);
        (uint256 whole, ) = mkulima.ConvertRawCheeriesToProduct(
            STARTING_KGS_TO_SELL
        );
        console.log(whole);
        assertEq(whole, 20);
    }

    function testConvertRawToProductWithRemainder() public {
        (, uint256 remainder) = mkulima.ConvertRawCheeriesToProduct(13);
        assertEq(remainder, 200);
    }

    function testRevertsifLessKilosIsProvided() public {
        vm.prank(FARMER);
        vm.expectRevert(Mkulima.Mkulima__NotEnoughKilosOfCheeries.selector);
        mkulima._AmountOfEthtoBeSentToKeepers(2);
    }

    // with no remainder
    function testWithNoRemainder() public {
        vm.prank(FARMER);
        // 50 does not have a remainder in a ratio of 5: 2
        (uint256 totaleth, uint256 amountOfEthWhole, ) = mkulima
            ._AmountOfEthtoBeSentToKeepers(50);
        // 20 kgs give 600 dollars amount of eth, which is 3 * 10^17

        assertEq(totaleth, amountOfEthWhole);
        assertEq(PRICE_OF_20KGS_IN_WEI, amountOfEthWhole);
    }

    function testwithRemainder() public {
        vm.prank(FARMER);
        (
            uint256 totaleth,
            uint256 amountEthWhole,
            uint256 ethValueOfRemainder
        ) = mkulima._AmountOfEthtoBeSentToKeepers(13);
        assertEq(totaleth, amountEthWhole + ethValueOfRemainder);
    }
}
