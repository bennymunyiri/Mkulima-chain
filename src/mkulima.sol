// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title Mkulima
 * @dev Mkulima is a contract for managing the production of Coffee with trust. The contract allows the "Mkulima"aka Farmer to sell his raw cheeries
 * in kg, then the factory will release the base amount in eth, to a mkulima address contract that will ensure no fradulent activities, if there is fradulent activites the eth in
 * the eth will be availble for withdrawal to the respective "Mkulima".
 * Otherwise,
 * When all goes well, the payment from the buyer in Auction.sol will Automatically send the Collateral to the 70% "Mkulima" and the 20 %factory.sol and later will implement 10% paid yearly
 * as Tax as it should be here https://www.kra.go.ke/business/companies-partnerships/companies-partnerships-pin-taxes/companies-partnerships-file-pay#:
 * @dev this will be Handled By safe to well store each mkulima data respectively
 * @dev chainlink in automation in auction.sol and getting the prices.
 *
 */

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {PriceConverter} from "./PriceConverter.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Factory} from "./Factory.sol";

contract Mkulima is ReentrancyGuard {
    //////////////////////////////
    //////  Errors  /////////
    /////////////////////////////

    error Mkulima__NotEnoughKilosOfCheeries();
    error Mkulima__NotValidFarmer();
    error Mkulima__AlreadyCanSell();
    error Mkulima__OnlyChairPersonGivesRightToSell();
    error Mkulima__NotEnoughTokens();
    error Mkulima__WithdrawFailed();
    error Mkulima__NotTimeToSell();

    //////////////////////////////
    //////  Libraries /////////
    /////////////////////////////
    using PriceConverter for uint256;
    //////////////////////////////
    //////State Variables/////////
    /////////////////////////////

    // Farmers should right amount of coffee and should be valid
    struct Farmer {
        address mkulima;
        uint256 whole;
        uint256 remainder;
        uint256 totaleth;
        bool valid;
    }

    uint256 private constant RATIO_RAW_FINISHED_MULTIPLIER = 2;
    uint256 private constant RATIO_RAW_FINISHED_DIVIDER = 5;
    uint256 private constant MINIMUM_KILOS_OF_CHEERIES = 10;
    // 30 usd is the minimum per kg of ready to sell coffee instead of the old corrupt way of 0.30 usd per kg.
    // https://www.the-star.co.ke/news/2023-08-02-release-sh25bn-fund-to-cushion-coffee-farmers-wamuchomba-tells-state/
    uint256 public constant MINIMUM_USD_PER_KG = 30e18;

    uint256 private constant PRICE_OF_ONE_ETH = 1;
    uint256 private constant DECIMALS = 1;
    uint256 private constant PRECISION = 1e10;
    uint256 private constant PRECISION_DECIMAL = 100;
    uint256 private constant PRECISION_REMAINDER = 10;

    mapping(address mkulima => Farmer) private s_mkulima;
    mapping(address owner => uint256 wEth) private s_keeperwEth;

    enum Sellstate {
        OPEN,
        SELLING,
        CLOSED
    }

    Sellstate public s_sellState;
    Farmer[] public farmers;
    uint256 private immutable i_minCheery;
    AggregatorV3Interface s_priceFeed;
    address public chairperson;
    Factory factory;
    /////////////////////////////
    /////Events//////
    /////////////////////////////

    event kgtoSell(address indexed mkulima, uint256 indexed amountEthAtKeepers);
    event WithdrawofEth(
        address indexed from,
        address indexed to,
        address wEth,
        uint256 amount
    );

    /////////////////////////////
    /////Modifier//////
    /////////////////////////////
    modifier MustBeEnough(uint256 mycheeries) {
        if (mycheeries < MINIMUM_KILOS_OF_CHEERIES) {
            revert Mkulima__NotEnoughKilosOfCheeries();
        }
        _;
    }
    modifier greaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert Mkulima__NotEnoughTokens();
            _;
        }
    }

    /////////////////////////////
    /////Constructor//////
    /////////////////////////////
    constructor(address priceFeed) {
        s_priceFeed = AggregatorV3Interface(priceFeed);
        i_minCheery = MINIMUM_KILOS_OF_CHEERIES;
        chairperson = msg.sender;
    }

    /////////////////////////////
    /////External Function//////
    /////////////////////////////

    // This function will allow on to sell his/her coffe
    //only if the farmer is verified.
    function SellCoffee(
        uint256 myrawcoffee
    )
        external
        MustBeEnough(myrawcoffee)
        nonReentrant
        returns (
            address mkulima,
            uint256 whole,
            uint256 remainder,
            uint256 totaleth
        )
    {
        if (s_sellState == Sellstate.SELLING) {
            revert Mkulima__NotTimeToSell();
        }
        if (s_mkulima[msg.sender].valid) {
            (uint256 wholeKilo, uint256 remain) = ConvertRawCheeriesToProduct(
                myrawcoffee
            );
            (uint256 totalEth, , ) = _AmountOfEthtoBeSentToKeepers(myrawcoffee);
            Farmer storage farmer = s_mkulima[msg.sender];
            farmer.mkulima = msg.sender;
            farmer.whole = wholeKilo;
            farmer.remainder = remain;
            farmer.totaleth = totalEth;
            s_keeperwEth[farmer.mkulima] = totalEth;
            emit kgtoSell(msg.sender, totalEth);
            farmers.push(farmer);
            return (
                farmer.mkulima,
                farmer.whole,
                farmer.remainder,
                farmer.totaleth
            );
        } else {
            // error fix
            revert Mkulima__NotValidFarmer();
        }
    }

    // follows checks effects Interactions
    // function Withdraw(
    //    address wEth,
    //     uint256 amount
    //  ) public greaterThanZero(amount) nonReentrant {
    //      _withdraw(wEth, amount, msg.sender, msg.sender);
    //  }

    // give right to a farmer to sell Coffee
    function giveRightToFarmers(address rightToSell) external {
        if (msg.sender != chairperson) {
            revert Mkulima__OnlyChairPersonGivesRightToSell();
        }
        if (s_mkulima[rightToSell].valid) {
            revert Mkulima__AlreadyCanSell();
        }
        // farmer can now sell his coffee
        s_mkulima[rightToSell].valid = true;
    }

    function receivePayment() external {}

    /////////////////////////////
    /////Internal Function//////
    /////////////////////////////
    /**
     *
     * @param amountofcoffee well 1 kg is sold at 80$ - 100$ dollars in most countries.
     * so it is reasonable to say the base price of coffee to sell from farmers to factory is 30 - 50 dollars. as per this article https://farmerstrend.co.ke/trending/coffee-farming-in-kenya-can-you-make-money-today/
     * to account that always mkulima's are paid are paid at least 30 dollars for 1 kg of there coffee
     */
    function _AmountOfEthtoBeSentToKeepers(
        uint256 amountofcoffee
    )
        public
        view
        MustBeEnough(amountofcoffee)
        returns (
            uint256 totaleth,
            uint256 amountOfEthWhole,
            uint256 ethValueOfRemainder
        )
    {
        (uint256 wholekilos, uint256 remainder) = ConvertRawCheeriesToProduct(
            amountofcoffee
        );
        uint256 amountOneOfEth = getUsdValueOfOneEth();
        // get price of 30 dollars in eth per whole kilo
        amountOfEthWhole =
            ((MINIMUM_USD_PER_KG * wholekilos) / (amountOneOfEth * PRECISION)) *
            PRECISION;
        ethValueOfRemainder =
            (((MINIMUM_USD_PER_KG * remainder) / PRECISION_REMAINDER) /
                (amountOneOfEth * PRECISION)) *
            PRECISION;
        // get price of 30 dollars in eth per remainder kilo
        totaleth = (amountOfEthWhole + ethValueOfRemainder);

        return (totaleth, amountOfEthWhole, ethValueOfRemainder);
    }

    function _withdraw() external {}

    /**
     * @param  rawcheeries This are the raw Cheeries which, this Convert function will give of how many kilos of final coffee it can produced
     * for this example am going to use the Arabica Breed, "Most Grown In Kenya", Example where 50kgs of raw cheeries, give a approximately 20 kgs of the final product.
     * so ratio of kgs of raw cheeries to final product is 5:2.
     * the functions also handles remainder for example, if the farmer sell 13 kgs of Arabica well. the ratio of 13 kgs will give out
     * 5.2 but in solidity their no decimals so well return the remainder to upto DECIMALS = 3, it will be 200.
     */
    function ConvertRawCheeriesToProduct(
        uint256 rawcheeries
    )
        public
        pure
        MustBeEnough(rawcheeries)
        returns (uint256 wholekilos, uint256 remainder)
    {
        wholekilos =
            (rawcheeries * RATIO_RAW_FINISHED_MULTIPLIER) /
            RATIO_RAW_FINISHED_DIVIDER;
        remainder =
            (((rawcheeries * RATIO_RAW_FINISHED_MULTIPLIER) %
                RATIO_RAW_FINISHED_DIVIDER) *
                (MINIMUM_KILOS_OF_CHEERIES ** DECIMALS)) /
            RATIO_RAW_FINISHED_DIVIDER;
        return (wholekilos, remainder);
    }

    function getUsdValueOfOneEth() public view returns (uint256) {
        return PRICE_OF_ONE_ETH.getConversionRate(s_priceFeed);
    }

    function getUsdValueofTotaleth(
        uint256 amount
    ) public view returns (uint256) {
        (uint256 total, , ) = _AmountOfEthtoBeSentToKeepers(amount);
        return (total.getConversionRate(s_priceFeed)) / 1 ether;
    }

    function getMkulimasSelling() public view returns (Farmer[] memory) {
        return farmers;
    }

    function getChairPerson() public view returns (address) {
        return chairperson;
    }

    function getStateOfBiashara() public view returns (Sellstate) {
        return s_sellState;
    }

    // add method to sell more coffee to the farmer if already in farmers array
    // give me right to sell
}
