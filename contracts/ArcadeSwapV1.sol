// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IBEP20Price.sol";
import "./libraries/Requests.sol";
import "./GameCurrency.sol";

contract ArcadeSwapV1 is Ownable, Pausable, ReentrancyGuard {
    using Request for Requests.Request;
    using SafeERC20 for IERC20;

    IBEP20Price public bep20Price;
    IERC20 public arcToken;
    GameCurrency public gcToken;
    uint256 public gcPerArc;

    struct GameInfo {
        uint256 id; // game id
        IERC20 gcToken;
        bool isActive;
        bool isPartnership; // true if the game is a partnership game
    }

    struct UserInfo {
        uint256 weightedAverage; // in 18 digits
        uint256 arcAmount; // in 18 digits
        uint256 gcAmount; // in 18 digits
    }

    // <game id => <user address => UserInfo>>
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => GameInfo) public gameInfo;

    struct Commission {
        uint256 commission1; // 100% in 10000
        uint256 commission2; // 100% in 10000
        address treasuryAddress1;
        address treasuryAddress2;
    }
    mapping(uint256 => Commission) internal _commissions;

    bytes32 public immutable BACKEND_DOMAIN_SEPARATOR;
    address public backendSigner;

    event BuyGameCurrency(
        uint256 indexed _gameId,
        address indexed _user,
        uint256 _arcAmount,
        uint256 _received,
        uint256 _minted
    );

    event SellGameCurrency(
        uint256 indexed _gameId,
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

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        BACKEND_DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyContract),
                keccak256("ArcadeSwap"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );
    }

    function setGcPerArc(uint256 _gcPerArc) external {
        require(_gcPerArc > 0, "non-zero GC to ARC");
        gcPerArc = _gcPerArc;
    }

    function setBackendSigner(address _signer) external {
        require(_signer != address(0), "invalid signer address");
        backendSigner = _signer;
    }

    function pause() external onlyOwner whenNotPaused {
        _pause();
    }

    function unpause() external onlyOwner whenPaused {
        _unpause();
    }

    function setGame(GameInfo memory _game) external onlyOwner {
        require(gameInfo[_game.id] != _game.id, "Already initialized");

    }

    function setGameActive(uint256 _gameId, bool active) external onlyOwner {
        require(gameInfo[_gameId].id == _gameId, "Not initialized game");
    }

    function buyGc(Requests.Request memory request)
        public
        virtual
        nonReentrant
        whenNotPaused
    {
        request.validate();
        request.verify(BACKEND_DOMAIN_SEPARATOR);
        require(request.maker == backendSigner, "invalid signer");

        // distribute commission
        uint256 commission1 =
            _amount * _commissions[_gameId].commission1 / 10000;
        uint256 commission2 =
            _amount * _commissions[_gameId].commission2 / 10000;
        if (commission1 > 0) {
            arcToken.safeTransferFrom(
                msg.sender,
                _commissions[_gameId].treasuryAddress1,
                commission1
            );
        }
        if (commission2 > 0) {
            arcToken.safeTransferFrom(
                msg.sender,
                _commissions[_gameId].treasuryAddress2,
                commission2
            );
        }

        arcToken.safeTransferFrom(
            msg.sender,
            address(this),
            _amount - commission1 - commission2
        );

        uint256 arcPrice = bep20Price.getTokenPrice(address(arcToken), 18);
        // GC token amount to be received in 18 digits
        uint256 toReceive = gcPerArc * arcPrice * _amount / 10 ** 18;

        uint256 weightedAverage = userInfo[_gameId][msg.sender].weightedAverage;
        weightedAverage =
            weightedAverage * userInfo[_gameId][msg.sender].arcAmount /
            10 ** 18 +
            _amount * arcPrice / 10 ** 18;
        userInfo[_gameId][msg.sender].arcAmount += _amount;
        userInfo[_gameId][msg.sender].weightedAverage =
            weightedAverage * 10 ** 18 /
            userInfo[_gameId][msg.sender].arcAmount;
        userInfo[_gameId][msg.sender].gcAmount += toReceive;

        gcToken.mint(msg.sender, toReceive);

        emit BuyGameCurrency(
            _gameId,
            msg.sender,
            _amount,
            toReceive,
            toReceive
        );
    }

    function sellGc(Requests.Request memory request)
        public
        virtual
        nonReentrant whenNotPaused
    {
        request.validate();
        request.verify(BACKEND_DOMAIN_SEPARATOR);
        require(request.maker == backendSigner, "invalid signer");

        require(
            userInfo[_gameId][msg.sender].gcAmount >= request.amount,
            "not enough game currency"
        );
        require(
            userInfo[_gameId][msg.sender].weightedAverage > 0,
            "invalid weighted average"
        );

        uint256 toReceive =
            _amount * (10 ** 18) /
            (gcPerArc * userInfo[_gameId][msg.sender].weightedAverage);

        // distribute commission
        uint256 commission1 =
            toReceive * _commissions[_gameId].commission1 / 10000;
        uint256 commission2 =
            toReceive * _commissions[_gameId].commission2 / 10000;
        if (commission1 > 0) {
            arcToken.safeTransfer(
                _commissions[_gameId].treasuryAddress1,
                commission1
            );
        }
        if (commission2 > 0) {
            arcToken.safeTransfer(
                _commissions[_gameId].treasuryAddress2,
                commission2
            );
        }

        arcToken.safeTransfer(
            msg.sender,
            toReceive - commission1 - commission2
        );
        gcToken.burn(msg.sender, _amount);

        userInfo[_gameId][msg.sender].arcAmount -= toReceive;
        userInfo[_gameId][msg.sender].gcAmount -= _amount;

        emit SellGameCurrency(
            _gameId,
            msg.sender,
            _amount,
            toReceive,
            _amount
        );
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

    /**
     * @notice Set commission per game
     * @param _id game id
     * @param _commission1 first commission percent in 10000(100%)
     * @param _commission2 second commission percent in 10000(100%)
     * @param _treasury1 first treasury address
     * @param _treasury2 second treasury address
     */
    function setCommission(
        uint256 _id,
        uint256 _commission1,
        uint256 _commission2,
        address _treasury1,
        address _treasury2
    ) external onlyOwner {
        require(_id != 0, "game id can't be zero");
        _commissions[_id] = Commission({
            commission1: _commission1,
            commission2: _commission2,
            treasuryAddress1: _treasury1,
            treasuryAddress2: _treasury2
        });
    }

    /**
     * @notice View commission per game
     * @param _id game id
     * @return commission structure
     */
    function viewCommission(uint256 _id)
        external
        view
        returns (Commission memory)
    {
        require(_id != 0, "game id can't be zero");
        return _commissions[_id];
    }
}