//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Mkulima} from "./mkulima.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IMkulima} from "./mkulimainterface.sol";

contract Factory is ReentrancyGuard {
    /////////////
    ///Errors////
    /////////////

    error Factory__OnlyChairPersonGivesRightToBuy();
    error Factory__AlreadyCanBuy();
    error Factory__ShouldBeMoreThanZero();
    error Factory__NotCorrectAddress();
    error Factory__OnlyValidCanDeposit();
    error Factory__DepositFailed();
    error Factory__CannotBuyStabilityMustbeOver80();
    error Factory__TransferFailed();
    //////////////////////////////
    //////State Variables////////
    /////////////////////////////

    struct FactoryData {
        address factory;
        bool valid;
        uint256 amountEth;
        uint256 amountCoffeeWhole;
        uint256 amountCoffeeRemainder;
    }

    uint256 private constant ETH_ALWAYS_100_PERCENT = 100;
    uint256 private constant ETH_ALWAYS_20_REMAINDER = 20;
    mapping(address wEth => address priceEth) private s_priceFeed;
    mapping(address factory => FactoryData) private s_factory;
    mapping(uint256 coffeebought => uint256 amountinEth) private s_totalamount;

    enum FactoryState {
        OPEN,
        CLOSED
    }

    address public chairperson;
    FactoryState public s_factoryState;
    address public s_depositWeth;
    address[] public s_factories;
    Mkulima public farmer;

    //////////////
    ///Events/////
    /////////////
    event DepositOfWeth(address indexed factory, uint256 indexed amount);
    event BuyingCoffee(
        address indexed boughtFrom,
        address indexed factoybought,
        uint256 amount
    );

    ///////////////
    ///Constructor////
    //////////////////
    constructor(address mkulima) {
        chairperson = msg.sender;
        s_factoryState = FactoryState.OPEN;
        farmer = Mkulima(mkulima);
    }

    ///////////////
    ///Modifiers////
    //////////////////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert Factory__ShouldBeMoreThanZero();
        }
        _;
    }
    modifier isNotAddressZero(address wEth) {
        if (s_priceFeed[wEth] == address(0)) {
            revert Factory__NotCorrectAddress();
        }
        _;
    }

    ///////////////
    /// interface////
    /////////////////////

    // this function stakes eth as  Collateral for the coffee to make the factory always trustworthy
    // not to buy more than 80% of the coffee from the farmers
    // NOTE also that the keepers will be the ones to send the eth back to the factory if the factory. forwards the to Auction.sol for buyers to buy
    // so the ether is to make sure they always stay Honest and Transparent

    /**
     *
     * Depositing will be done  so as the factory can have collateral to buy coffee from farmers for processing.
     * @param amount The amount wEth that the Factory will use as Collateral.
     */

    function depositingeth(
        uint256 amount
    ) external payable moreThanZero(amount) nonReentrant {
        if (s_factory[msg.sender].valid) {
            FactoryData storage factory = s_factory[msg.sender];
            factory.amountEth += amount;
            emit DepositOfWeth(msg.sender, amount);
        } else {
            revert Factory__OnlyValidCanDeposit();
        }
    }

    // punishment if they dont forward the coffee to the auction.sol
    // transfer eth from this contract to farmers contract.

    function ispunishment() external {
        if (s_factory[msg.sender].valid) {
            FactoryData storage factory = s_factory[msg.sender];
            uint256 amountEth = factory.amountEth;
            factory.amountEth = 0;
            if (!payable(msg.sender).send(amountEth)) {
                revert Factory__TransferFailed();
            }
        }
    }

    // this function will be called by the factory to buy coffee from the farmers
    function buyingCoffee() external {
        if (s_factoryState == FactoryState.CLOSED) {
            revert Factory__CannotBuyStabilityMustbeOver80();
        }
        if (s_factory[msg.sender].valid) {
            FactoryData storage factory = s_factory[msg.sender];
            uint256 amountEth = factory.amountEth;
            uint256 amountCoffeeWhole = factory.amountCoffeeWhole;
            (address mkulima, uint256 whole, uint256 remainder, ) = farmer
                .SellCoffee(amountCoffeeWhole);

            factory.amountCoffeeWhole = whole;
            factory.amountCoffeeRemainder = remainder;
            factory.amountEth = amountEth - amountEth;
            s_totalamount[whole] = amountEth;

            emit BuyingCoffee(mkulima, msg.sender, whole);
        }
    }

    /*
     * @param myrightTobuy Factories can only operate if the chairperson has given right to operate
     */
    function rightToBuy(address myrightTobuy) external {
        if (msg.sender != chairperson) {
            revert Factory__OnlyChairPersonGivesRightToBuy();
        }
        if (s_factory[myrightTobuy].valid) {
            revert Factory__AlreadyCanBuy();
        }
        s_factory[myrightTobuy].valid = true;
        s_factories.push(myrightTobuy);
    }

    // this function checks if the stability of eth is always 80% of the amount remaining in the contract. if there is less than
    // 20% of amount of eth in the factory the state changes to wait
    // this is to ensure the algorithm always work. to buy only upto 80% of the farmers coffee
    function _checkStability() internal {
        uint256 amountEth = getamountofEthStaked();
        uint256 twentypercent = (amountEth * ETH_ALWAYS_20_REMAINDER) /
            ETH_ALWAYS_100_PERCENT;
        if (amountEth <= twentypercent) {
            // Factory state if its less or equal to 20%
            s_factoryState = FactoryState.CLOSED;
        } else {
            s_factoryState = FactoryState.OPEN;
        }
    }

    /////////////////////
    /////pure and view/////////
    //////////////////////

    function getamountofEthStaked() public view returns (uint256 amountEth) {
        if (s_factory[msg.sender].valid) {
            FactoryData storage factory = s_factory[msg.sender];
            return factory.amountEth;
        }
    }

    function getfactories(uint256 index) public view returns (address) {
        return s_factories[index];
    }

    function getmkulimaselling(
        uint256 amount,
        address contractadrr
    )
        external
        view
        returns (
            address mkulima,
            uint256 whole,
            uint256 remainder,
            uint256 totaleth
        )
    {
        return IMkulima(contractadrr).sellCoffee(amount);
    }
}
