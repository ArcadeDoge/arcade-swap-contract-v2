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
    using Requests for Requests.Request;
    using SafeERC20 for IERC20;

    IBEP20Price public bep20Price;
    IERC20 public arcToken;

    struct GameInfo {
        uint256 id; // game id
        uint256 gcPerArc;
        IERC20 gcToken;
        string gcName;
        string gcSymbol;
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

    bytes32 public immutable DOMAIN_SEPARATOR;
    address public backendSigner;

    event NewGame(
        uint256 indexed _gameId,
        uint256 indexed _gcPerArc,
        address indexed _gcToken,
        string _gcName,
        string _gcSymbol,
        bool _isPartnership
    );

    event GameActive(uint256 indexed _gameId, bool _active);

    event GameGcPerArc(uint256 indexed _gameId, uint256 _gcPerArc);

    event GamePartnership(uint256 indexed _gameId, bool _partnership);

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

    modifier isActiveGame(uint256 _gameId) {
        require(gameInfo[_gameId].id == _gameId, "not initialized game");
        require(gameInfo[_gameId].isActive, "inactive game");
        _;
    }

    constructor(
        IBEP20Price _bep20Price,
        IERC20 _token
    ) {
        bep20Price = _bep20Price;
        arcToken = _token;

        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("ArcadeSwap"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );
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

    function setNewGame(
        uint256 _gameId,
        uint256 _gcPerArc,
        string memory _gcName,
        string memory _gcSymbol,
        bool isPartnership
    ) external onlyOwner {
        require(gameInfo[_gameId].id != _gameId, "Already initialized");
        require(_gcPerArc > 0, "invalid game currency amount per arc token");
        GameCurrency gcToken = new GameCurrency(_gcName, _gcSymbol);
        gameInfo[_gameId] = GameInfo({
            id: _gameId,
            gcPerArc: _gcPerArc,
            gcName: _gcName,
            gcSymbol: _gcSymbol,
            gcToken: IERC20(gcToken),
            isActive: true,
            isPartnership: isPartnership
        });

        emit NewGame(
            _gameId,
            _gcPerArc,
            address(gcToken),
            _gcName,
            _gcSymbol,
            isPartnership
        );
    }

    function setGameActive(uint256 _gameId, bool _active) external onlyOwner {
        gameInfo[_gameId].isActive = _active;

        emit GameActive(_gameId, _active);
    }

    function setGameGcPerArc(uint256 _gameId, uint256 _gcPerArc)
        external onlyOwner isActiveGame(_gameId)
    {
        require(_gcPerArc > 0, "invalid game currency amount per arc token");
        gameInfo[_gameId].gcPerArc = _gcPerArc;

        emit GameGcPerArc(_gameId, _gcPerArc);
    }

    function setPartnership(uint256 _gameId, bool _partnership)
        external onlyOwner isActiveGame(_gameId)
    {
        gameInfo[_gameId].isPartnership = _partnership;

        emit GamePartnership(_gameId, _partnership);
    }

    function buyGc(Requests.Request memory request)
        public
        virtual
        nonReentrant
        whenNotPaused
        isActiveGame(request.gameId)
    {
        request.validate();
        request.verify(DOMAIN_SEPARATOR);
        require(request.maker == backendSigner, "invalid signer");
        require(
            request.gcToken == address(gameInfo[request.gameId].gcToken),
            "invalid game currency token"
        );

        uint256 gameId = request.gameId;

        // distribute commission
        uint256 commission1 =
            request.amount * _commissions[gameId].commission1 / 10000;
        uint256 commission2 =
            request.amount * _commissions[gameId].commission2 / 10000;
        if (commission1 > 0) {
            arcToken.safeTransferFrom(
                msg.sender,
                _commissions[gameId].treasuryAddress1,
                commission1
            );
        }
        if (commission2 > 0) {
            arcToken.safeTransferFrom(
                msg.sender,
                _commissions[gameId].treasuryAddress2,
                commission2
            );
        }

        arcToken.safeTransferFrom(
            msg.sender,
            address(this),
            request.amount - commission1 - commission2
        );

        uint256 arcPrice = bep20Price.getTokenPrice(address(arcToken), 18);
        // GC token amount to be received in 18 digits
        uint256 toReceive =
            gameInfo[gameId].gcPerArc * arcPrice * request.amount / 10 ** 18;

        uint256 weightedAverage = userInfo[gameId][msg.sender].weightedAverage;
        weightedAverage =
            weightedAverage * userInfo[gameId][msg.sender].arcAmount /
            10 ** 18 +
            request.amount * arcPrice / 10 ** 18;
        userInfo[gameId][msg.sender].arcAmount += request.amount;
        userInfo[gameId][msg.sender].weightedAverage =
            weightedAverage * 10 ** 18 /
            userInfo[gameId][msg.sender].arcAmount;
        userInfo[gameId][msg.sender].gcAmount += toReceive;

        GameCurrency(request.gcToken).mint(msg.sender, toReceive);

        emit BuyGameCurrency(
            gameId,
            msg.sender,
            request.amount,
            toReceive,
            toReceive
        );
    }

    function sellGc(Requests.Request memory request)
        public
        virtual
        nonReentrant
        whenNotPaused
        isActiveGame(request.gameId)
    {
        request.validate();
        request.verify(DOMAIN_SEPARATOR);
        require(request.maker == backendSigner, "invalid signer");
        require(
            request.gcToken == address(gameInfo[request.gameId].gcToken),
            "invalid game currency token"
        );

        uint256 gameId = request.gameId;

        require(
            userInfo[gameId][msg.sender].gcAmount >= request.amount,
            "not enough game currency"
        );
        require(
            userInfo[gameId][msg.sender].weightedAverage > 0,
            "invalid weighted average"
        );

        uint256 toReceive =
            request.amount * (10 ** 18) /
            (
                gameInfo[gameId].gcPerArc * userInfo[gameId][msg.sender].weightedAverage
            );

        // distribute commission
        uint256 commission1 =
            toReceive * _commissions[gameId].commission1 / 10000;
        uint256 commission2 =
            toReceive * _commissions[gameId].commission2 / 10000;
        if (commission1 > 0) {
            arcToken.safeTransfer(
                _commissions[gameId].treasuryAddress1,
                commission1
            );
        }
        if (commission2 > 0) {
            arcToken.safeTransfer(
                _commissions[gameId].treasuryAddress2,
                commission2
            );
        }

        arcToken.safeTransfer(
            msg.sender,
            toReceive - commission1 - commission2
        );
        GameCurrency(request.gcToken).burn(msg.sender, request.amount);

        userInfo[gameId][msg.sender].arcAmount -= toReceive;
        userInfo[gameId][msg.sender].gcAmount -= request.amount;

        emit SellGameCurrency(
            gameId,
            msg.sender,
            request.amount,
            toReceive,
            request.amount
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
     * @param _gameId game id
     * @param _commission1 first commission percent in 10000(100%)
     * @param _commission2 second commission percent in 10000(100%)
     * @param _treasury1 first treasury address
     * @param _treasury2 second treasury address
     */
    function setCommission(
        uint256 _gameId,
        uint256 _commission1,
        uint256 _commission2,
        address _treasury1,
        address _treasury2
    ) external onlyOwner {
        require(_gameId != 0, "game id can't be zero");
        _commissions[_gameId] = Commission({
            commission1: _commission1,
            commission2: _commission2,
            treasuryAddress1: _treasury1,
            treasuryAddress2: _treasury2
        });
    }

    /**
     * @notice View commission per game
     * @param _gameId game id
     * @return commission structure
     */
    function viewCommission(uint256 _gameId)
        external
        view
        returns (Commission memory)
    {
        require(_gameId != 0, "game id can't be zero");
        return _commissions[_gameId];
    }
}