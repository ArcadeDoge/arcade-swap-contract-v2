// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../interface/IBEP20Price.sol";

contract MockBEP20Price is Ownable, IBEP20Price {
    using SafeMath for uint256;

    uint256 private _tokenPrice = 30 * 10 ** 18;

    function setTokenPrice(address _token, uint256 _price) external onlyOwner {
        _tokenPrice = _price;
    }

    /**
     * @notice Get BNB price in USD
     * price = real_price * 10 ** 18
     * @return uint256 returns BNB price in usd
     */
    function getBNBPrice() external override pure returns (uint256) {
        return 30 * 10 ** 18;
    }

    /**
   * @notice Calculate token price in USD
   * @param _token BEP20 token address
   * @param _digits BEP20 token digits
   * @return return in 18 digits
   */
    function getTokenPrice(
        address _token,
        uint256 _digits
    ) external override view returns (uint256) {
        return _tokenPrice;
    }
}