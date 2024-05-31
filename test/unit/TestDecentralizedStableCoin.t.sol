// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDecentralizedStableCoin} from "../../script/DeployDecentralizedStableCoin.s.sol";
import "forge-std/console.sol";

contract RaffleTest is Test {
    address public PLAYER = address(this); // Creates an address derived from the provided name.
    uint256 public constant STARTING_BALANCE = 10000e18;
    DeployDecentralizedStableCoin deployDecentralizedStableCoin;

    DecentralizedStableCoin dsc;

    function setUp() external {
        deployDecentralizedStableCoin = new DeployDecentralizedStableCoin();
        dsc = deployDecentralizedStableCoin.run();
        //deal(address(dsc), PLAYER, STARTING_BALANCE); // Sends ether to the specified address
    }

    // function testBurn() external {
    //     console.log("Script testBurn", address(this));
    //     vm.prank(address(deployDecentralizedStableCoin));
    //     uint256 balance = dsc.balanceOf(PLAYER);
    //     dsc.burn(balance);
    //     assertEq(dsc.balanceOf(PLAYER), 0);
    // }
}
