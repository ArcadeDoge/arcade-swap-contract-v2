// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "hardhat/console.sol";
import "./abstracts/ArcadeUpgradeable.sol";
import "./interface/IBEP20Price.sol";
import "./libraries/Requests.sol";
import "./GameCurrency.sol";

contract ArcadeSwapV1 is ArcadeUpgradeable {
    using Requests for Requests.Request;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IBEP20Price public bep20Price;
    IERC20Upgradeable public arcToken;

    struct GameInfo {
        uint256 id; // game id
        uint256 gcPerUSD;
        address gcToken; // address to GameCurrency
        string gcName;
        string gcSymbol;
        bool isActive;
    }

    struct UserInfo {
        uint256 weightedAverage; // in 18 digits
        uint256 gcAmount; // in 18 digits
        int256 arcAmount; // in 18 digits
    }

    // <game id => <user address => UserInfo>>
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping (uint256 => GameInfo) public gameInfo;
    mapping (uint256 => address[]) public gameUsers;
    mapping (uint256 => mapping (address => bool)) public gameUsersAdded;

    struct Commission {
        uint256 commission1; // 100% in 10000
        uint256 commission2; // 100% in 10000
        address treasuryAddress1;
        address treasuryAddress2;
    }
    mapping(uint256 => Commission) internal _commissions;

    uint256 public txDuration;
    // <user address, <game id => timestamp>>
    mapping (address => mapping(uint256 => uint256)) public lastTxTime;

    bytes32 public DOMAIN_SEPARATOR;
    address public backendSigner;

    event NewGame(
        uint256 indexed _gameId,
        uint256 indexed _gcPerUSD,
        address indexed _gcToken,
        string _gcName,
        string _gcSymbol
    );

    event GameActive(uint256 indexed _gameId, bool _active);

    event GameGcPerUSD(uint256 indexed _gameId, uint256 _gcPerUSD);

    event ClearUser(uint256 indexed _gameId, address indexed _user);

    event ClearGame(uint256 indexed _gameId);

    event SwapGameCurrency(
        uint256 indexed _type, // 1: buyGc, 2: sellGc
        uint256 indexed _gameId,
        address indexed _user,
        uint256 _amount,
        uint256 _received,
        uint256 _minted
    );

    // emit event when user transfer Gc from wallet to the game
    event TransferWalletToGame(
        uint256 indexed _gameId,
        address indexed _user,
        uint256 _gcAmount
    );

    // emit event when user transfer Gc from game to wallet
    event TransferGameToWallet(
        uint256 indexed _gameId,
        address indexed _user,
        uint256 _gcAmount
    );

    event SetTxDuration(uint256 _duration);

    modifier isActiveGame(uint256 _gameId) {
        require(gameInfo[_gameId].id == _gameId, "not initialized game");
        require(gameInfo[_gameId].isActive, "inactive game");
        _;
    }

    constructor() {
        
    }

    function __ArcadeSwap_init(
        IBEP20Price _bep20Price,
        IERC20Upgradeable _token
    ) public initializer {
        ArcadeUpgradeable.initialize();

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

    function setArcToken(IERC20Upgradeable _arcToken) external onlyOwner {
        arcToken = _arcToken;
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
        uint256 _gcPerUSD,
        string memory _gcName,
        string memory _gcSymbol
    ) external onlyOwner {
        require(gameInfo[_gameId].id != _gameId, "Already initialized");
        require(_gcPerUSD > 0, "invalid game currency amount per arc token");
        GameCurrency gcToken = new GameCurrency(
            _gcName,
            _gcSymbol
        );
        gameInfo[_gameId] = GameInfo({
            id: _gameId,
            gcPerUSD: _gcPerUSD,
            gcName: _gcName,
            gcSymbol: _gcSymbol,
            gcToken: address(gcToken),
            isActive: true
        });

        emit NewGame(
            _gameId,
            _gcPerUSD,
            address(gcToken),
            _gcName,
            _gcSymbol
        );
    }

    function setGameActive(uint256 _gameId, bool _active) external onlyOwner {
        gameInfo[_gameId].isActive = _active;

        emit GameActive(_gameId, _active);
    }

    function setGameGcPerUSD(uint256 _gameId, uint256 _gcPerUSD)
        external onlyOwner isActiveGame(_gameId)
    {
        require(_gcPerUSD > 0, "invalid game currency amount per arc token");
        gameInfo[_gameId].gcPerUSD = _gcPerUSD;

        emit GameGcPerUSD(_gameId, _gcPerUSD);
    }

    function mintGc(Requests.Request memory request)
        public
        virtual
        nonReentrant
        whenNotPaused
        isActiveGame(request.gameId)
    {
        request.validate();
        request.verify(DOMAIN_SEPARATOR);
        require(request.maker == backendSigner, "invalid signer");
        require(request.requester == msg.sender, "invalid requester");
        require(
            request.gcToken == gameInfo[request.gameId].gcToken,
            "invalid game currency token"
        );
        uint256 gameId = request.gameId;
        require(
            block.timestamp - lastTxTime[msg.sender][gameId] >= txDuration,
            "Not time to update Game Point"
        );

        userInfo[gameId][msg.sender].gcAmount += request.amount;
        
        GameCurrency(request.gcToken).mint(msg.sender, request.amount);

        lastTxTime[msg.sender][gameId] = block.timestamp;

        if (!gameUsersAdded[gameId][msg.sender]) {
            gameUsersAdded[gameId][msg.sender] = true;
            gameUsers[gameId].push(msg.sender);
        }
    }

    function burnGc(Requests.Request memory request)
        public
        virtual
        nonReentrant
        whenNotPaused
        isActiveGame(request.gameId)
    {
        request.validate();
        request.verify(DOMAIN_SEPARATOR);
        require(request.maker == backendSigner, "invalid signer");
        require(request.requester == msg.sender, "invalid requester");
        require(
            request.gcToken == gameInfo[request.gameId].gcToken,
            "invalid game currency token"
        );
        uint256 gameId = request.gameId;
        require(
            block.timestamp - lastTxTime[msg.sender][gameId] >= txDuration,
            "Not time to update Game Point"
        );

        userInfo[gameId][msg.sender].gcAmount -= request.amount;
        
        GameCurrency(request.gcToken).burn(msg.sender, request.amount);

        lastTxTime[msg.sender][gameId] = block.timestamp;
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
        require(request.requester == msg.sender, "invalid requester");
        require(
            request.gcToken == gameInfo[request.gameId].gcToken,
            "invalid game currency token"
        );
        uint256 gameId = request.gameId;
        require(
            block.timestamp - lastTxTime[msg.sender][gameId] >= txDuration,
            "Not time to buy Game Point"
        );

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
            gameInfo[gameId].gcPerUSD * arcPrice * request.amount / 10 ** 18;

        int256 weightedAverage = int256(
            userInfo[gameId][msg.sender].weightedAverage
        );
        weightedAverage =
            weightedAverage * userInfo[gameId][msg.sender].arcAmount /
            10 ** 18 +
            int256(request.amount * arcPrice / 10 ** 18);
        userInfo[gameId][msg.sender].arcAmount += int256(request.amount);
        userInfo[gameId][msg.sender].weightedAverage = uint256(
            weightedAverage * 10 ** 18 /
            userInfo[gameId][msg.sender].arcAmount
        );
        userInfo[gameId][msg.sender].gcAmount += toReceive;
        
        GameCurrency(request.gcToken).mint(msg.sender, toReceive);

        lastTxTime[msg.sender][gameId] = block.timestamp;

        if (!gameUsersAdded[gameId][msg.sender]) {
            gameUsersAdded[gameId][msg.sender] = true;
            gameUsers[gameId].push(msg.sender);
        }

        emit SwapGameCurrency(
            1, // BuyGc
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
        require(request.requester == msg.sender, "invalid requester");
        require(
            request.gcToken == gameInfo[request.gameId].gcToken,
            "invalid game currency token"
        );
        uint256 gameId = request.gameId;
        require(
            block.timestamp - lastTxTime[msg.sender][gameId] >= txDuration,
            "Not time to buy Game Point"
        );

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
                gameInfo[gameId].gcPerUSD * userInfo[gameId][msg.sender].weightedAverage
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

        userInfo[gameId][msg.sender].arcAmount -= int256(toReceive);
        userInfo[gameId][msg.sender].gcAmount -= request.amount;
        
        lastTxTime[msg.sender][gameId] = block.timestamp;

        emit SwapGameCurrency(
            2,
            gameId,
            msg.sender,
            request.amount,
            toReceive,
            request.amount
        );
    }

    function clearUser(uint256 _gameId, address _user) external onlyOwner {
        require(_user != address(0), "invalid parameter");
        userInfo[_gameId][_user].weightedAverage = 0;
        userInfo[_gameId][_user].arcAmount = 0;
        userInfo[_gameId][_user].gcAmount = 0;
    }

    function clearGame(uint256 _gameId, uint256 _startFrom, uint256 _endTo)
        external
        onlyOwner
    {
        require(_startFrom <= _endTo, "invalid parameter");
        require(_endTo < gameUsers[_gameId].length, "invalid paramter");
        for (uint256 i = _startFrom; i <= _endTo; i++) {
            UserInfo storage user = userInfo[_gameId][gameUsers[_gameId][i]];
            user.weightedAverage = 0;
            user.arcAmount = 0;
            user.gcAmount = 0;
        }
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

    /**
     * @notice Set transaction duration
     * @param _duration duration  in seconds
     */
    function setTxDuration(uint256 _duration) external onlyOwner {
        require(_duration > 0, "Non-zero duration");
        require(txDuration != _duration, "Different duration");
        txDuration = _duration;
        emit SetTxDuration(_duration);
    }
}