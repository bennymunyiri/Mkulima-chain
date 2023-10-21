// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

interface IMkulima {
    function sellCoffee(
        uint256 amount
    )
        external
        view
        returns (
            address mkulima,
            uint256 whole,
            uint256 remainder,
            uint256 totaleth
        );
}
