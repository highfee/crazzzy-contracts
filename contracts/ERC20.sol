// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract CrazzyMonsterERC20Token is ERC20, Ownable, ERC20Permit {
    constructor()
        ERC20("CrazzyMonsterToken", "CBT")
        Ownable(msg.sender)
        ERC20Permit("CrazzyMonsterToken")
    {
        _mint(msg.sender, 10000000 * 10 ** decimals());
    }

    function mint(uint256 amount) public onlyOwner {
        _mint(msg.sender, amount);
    }
}
