// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IBEP20Price.sol";
import "./GameCurrency.sol";

contract ArcadeSwapV1 is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IBEP20Price public bep20Price;
    IERC20 public arcToken;
    GameCurrency public gcToken;
    uint256 public gcPerArc;

    struct GameInfo {
        uint256 id; // game id
        uint256 gcAmount;
        bool isPartnership; // true if the game is a partnership game
    }

    struct UserInfo {
        uint256 weightedAverage; // in 18 digits
        uint256 arcAmount; // in 18 digits
        uint256 gcAmount; // in 18 digits
    }

    mapping (address => UserInfo) public userInfo;
    mapping (uint256 => GameInfo) public gameInfo;

    event BuyGameCurrency(
        address indexed _user,
        uint256 _arcAmount,
        uint256 _received,
        uint256 _minted
    );

    event SellGameCurrency(
        address indexed _user,
        uint256 _gcAmount,
        uint256 _received,
        uint256 _burned
    );

    constructor(
        IBEP20Price _bep20Price,
        IERC20 _token,
        GameCurrency _gcToken,
        uint256 _gcPerArc
    ) {
        bep20Price = _bep20Price;
        arcToken = _token;
        gcToken = _gcToken;
        gcPerArc = _gcPerArc;
    }

    function setGcPerArc(uint256 _gcPerArc) external {
        require(_gcPerArc > 0, "non-zero GC to ARC");
        gcPerArc = _gcPerArc;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function buyGc(uint256 _amount) public virtual nonReentrant whenNotPaused {
        require(_amount > 0, "invalid amount");

        arcToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 arcPrice = bep20Price.getTokenPrice(address(arcToken), 18);
        // GC token amount to be received in 18 digits
        uint256 toReceive = gcPerArc * arcPrice * _amount / 10 ** 18;

        uint256 weightedAverage = userInfo[msg.sender].weightedAverage;
        weightedAverage =
            weightedAverage * userInfo[msg.sender].arcAmount / 10 ** 18 +
            _amount * arcPrice / 10 ** 18;
        userInfo[msg.sender].arcAmount += _amount;
        userInfo[msg.sender].weightedAverage =
            weightedAverage * 10 ** 18 / userInfo[msg.sender].arcAmount;
        userInfo[msg.sender].gcAmount += toReceive;

        gcToken.mint(msg.sender, toReceive);

        emit BuyGameCurrency(msg.sender, _amount, toReceive, toReceive);
    }

    function sellGc(uint256 _amount)
        public
        virtual
        nonReentrant whenNotPaused
    {
        require(_amount > 0, "invalid amount");
        require(
            userInfo[msg.sender].gcAmount >= _amount,
            "not enough game currency"
        );
        require(
            userInfo[msg.sender].weightedAverage > 0, "invalid weighted average"
        );

        uint256 toReceive =
            _amount * (10 ** 18) /
            (gcPerArc * userInfo[msg.sender].weightedAverage);
        
        gcToken.burn(msg.sender, _amount);
        arcToken.safeTransfer(msg.sender, toReceive);

        userInfo[msg.sender].arcAmount -= toReceive;
        userInfo[msg.sender].gcAmount -= _amount;

        emit SellGameCurrency(msg.sender, _amount, toReceive, _amount);
    }

    /** 
     * @notice withdraw Arcade token
     * @param _to "to" address of withdraw request
     * @param _amount amount to withdraw
     */
    function transferTo(address _to, uint256 _amount) external onlyOwner {
        require(_to != address(0), "Transfer to zero address.");
        require(arcToken.balanceOf(address(this)) >= _amount, "invalid amount");
        arcToken.safeTransfer(_to, _amount);
    }

    function setGamePartnership(uint256 _gameId, bool _partnership)
        external
        onlyOwner
    {
        gameInfo[_gameId].isPartnership = _partnership;
    }
}