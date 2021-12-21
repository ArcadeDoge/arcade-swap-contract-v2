// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

interface IBEP20Price {
  /**
   * @notice Return BNB price in USD
   * @return returns in 18 digits
   */
  function getBNBPrice() external view returns (uint256);

  /**
   * @notice Calculate token price in USD
   * @param _token BEP20 token address
   * @param _digits BEP20 token digits
   * @return return in 18 digits
   */
  function getTokenPrice(
    address _token,
    uint256 _digits
  ) external view returns (uint256);
}