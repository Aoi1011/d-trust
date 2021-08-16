// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/SchedulerInterface.sol";
import "./interfaces/IMyERC20.sol";
import "./interfaces/IMyERC721.sol";
import "./libraries/Strings.sol";

contract DTRUST is ERC1155 {
    // Library///////
    using Strings for string;
    /////////////////

    // constants/////
    uint256 private constant PACK_INDEX =
        0x0000000000000000000000000000000000000000000000000000000000007FFF;
    uint256 private constant PrToken = 0;
    uint256 private constant DToken = 1;
    /////////////////

    enum ContractRights {
        TERMINATE,
        SWAP,
        POSTPONE
    }

    struct ERC20TokenAsset {
        IMyERC20 erc20;
        uint256 erc20TokenId;
        uint256 erc20TokenAmount;
        uint256 erc20PaymentPerFrequency;
        address currentScheduledTransaction;
        uint256 paymentInterval;
        uint256 lockedUntil;
    }

    struct ERC721TokenAsset {
        IMyERC721 erc721;
        uint256 erc721TokenId;
        address currentScheduledTransaction;
        uint256 paymentInterval;
        uint256 lockedUntil;
    }

    struct PrTokenStruct {
        uint256 id;
        string tokenKey;
    }

    struct Subscription {
        uint256 start;
        uint256 nextPayment;
        bool isTwoYear;
    }

    SchedulerInterface public scheduler;

    uint256 private _AnualFeeTotal = 0;
    uint256 public basisPoint = 1; // for 2 year
    uint256 public countOfPrToken = 1;
    uint256 public payAnnualFrequency = 730 days;
    uint256[] private erc20assetIds;
    uint256[] private erc721assetIds;
    address payable public manager;
    address payable public settlor;
    address payable public trustee;
    address public beneficiary;
    string public name;
    string public symbol;
    string public dTrustUri;
    ERC20TokenAsset[] public erc20TokenAssets;
    ERC721TokenAsset[] public erc721TokenAssets;
    PrTokenStruct[] public prTokens;
    Subscription private subscription;

    // storage//////////////////////////
    mapping(uint256 => bool) public existToken;
    mapping(uint256 => uint256) public tokenSupply; // id -> tokensupply
    mapping(uint256 => uint256) public tokenPrices; // id -> tokenPrice
    mapping(address => mapping(uint256 => uint256)) private _orderBook; // customer -> id -> amount of asset
    /////////////////////////////////////

    // event/////////////////////////////
    event Order(
        address indexed _target,
        uint256 indexed _id,
        uint256 indexed _amount
    );
    event OrderBatch(
        address indexed _target,
        uint256[] indexed _ids,
        uint256[] indexed _amounts
    );
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);
    event TransferBatch(
        address indexed from,
        address indexed to,
        uint256[] value
    );
    event Mint(address indexed sender, uint256 tokenId, uint256 amount);
    event UpdateBasisPoint(uint256 basispoint);
    event PaymentSentForFirstTwoYear(
        address from,
        uint256 tokenId,
        uint256 amount,
        uint256 total,
        uint256 date
    );
    event PaymentSentForSubsequentYear(
        address from,
        uint256 amount,
        uint256 total,
        uint256 date
    );
    event PaymentScheduled(
        ERC20TokenAsset[] indexed erc20Assets,
        ERC721TokenAsset[] indexed erc721Assets,
        address recipient
    );
    event PaymentExecuted(
        address indexed scheduledTransaction,
        address recipient,
        uint256 value
    );
    event PayToBeneficiary(uint256[] ids, uint256[] amounts);
    ////////////////////////////////////////

    modifier onlyManager() {
        require(
            msg.sender == manager ||
                msg.sender == settlor ||
                msg.sender == trustee,
            "Error: The caller is not any of the defined managers (settlor and trustee)!"
        );
        _;
    }

    constructor(
        string memory _newURI,
        address payable _deployerAddress,
        address payable _settlor,
        address _beneficiary,
        address payable _trustee
    ) ERC1155(_newURI) {
        require(address(_deployerAddress) != address(0));
        require(address(_settlor) != address(0));
        require(address(_beneficiary) != address(0));
        require(address(_trustee) != address(0));

        dTrustUri = _newURI;
        manager = _deployerAddress;
        settlor = _settlor;
        beneficiary = _beneficiary;
        trustee = _trustee;

        scheduler = SchedulerInterface(_deployerAddress);

        subscription = Subscription(
            block.timestamp,
            block.timestamp + payAnnualFrequency,
            true
        );

        schedule();
    }

    fallback() external payable {
        if (msg.value > 0) {
            //this handles recieving remaining funds sent while scheduling (0.1 ether)
            return;
        }

        process();
    }

    receive() external payable {}

    function setURI(string memory _newURI) public onlyManager {
        _setURI(_newURI);
    }

    function getURI(string memory _uri, uint256 _id)
        public
        pure
        returns (string memory)
    {
        return toFullURI(_uri, _id);
    }

    function toFullURI(string memory _uri, uint256 _id)
        internal
        pure
        returns (string memory)
    {
        return
            string(
                abi.encodePacked(
                    _uri,
                    "/",
                    Strings.uint2str(_id & PACK_INDEX),
                    ".json"
                )
            );
    }

    function mint(
        address _to,
        uint256 _id,
        uint256 _quantity,
        bytes memory _data
    ) public onlyManager {
        _mint(_to, _id, _quantity, _data);
        tokenSupply[_id] += _quantity;
    }

    function mintBatch(
        uint256[] memory _ids,
        uint256[] memory _amounts,
        bytes memory _data
    ) public onlyManager {
        _mintBatch(manager, _ids, _amounts, _data);
        for (uint256 i = 0; i < _ids.length; i++) {
            existToken[_ids[i]] = true;
            tokenSupply[_ids[i]] = _amounts[i];
        }
    }

    function depositERC20Assets(
        IMyERC20[] memory erc20s,
        uint256[] memory _amounts,
        uint256[] memory _paymentPerFrequency,
        uint256[] memory _paymentIntervals,
        bytes calldata _data
    ) external payable onlyManager {
        for (uint256 i = 0; i < erc20s.length; i++) {
            uint256 id = uint256(uint160(address(erc20s[i])));
            erc20assetIds.push(id);

            ERC20TokenAsset memory newerc20 = ERC20TokenAsset(
                erc20s[i],
                id,
                _amounts[i],
                _paymentPerFrequency[i],
                address(0),
                _paymentIntervals[i],
                block.timestamp
            );
            erc20TokenAssets.push(newerc20);
            _orderBook[manager][id] = _amounts[i];

            require(
                erc20s[i].transferFrom(manager, address(this), _amounts[i]),
                "Cannot transfer."
            );
        }
        mintBatch(erc20assetIds, _amounts, _data);

        emit OrderBatch(manager, erc20assetIds, _amounts);
    }

    function depositERC721Assets(
        IMyERC721[] calldata _erc721Tokens,
        bytes calldata _data,
        uint256[] memory _paymentPerFrequency
    ) external payable onlyManager {
        uint256[] memory amounts = new uint256[](_erc721Tokens.length);
        for (uint256 i = 0; i < _erc721Tokens.length; i++) {
            uint256 _erc1155TokenId = _tokenHash(_erc721Tokens[i]);
            erc721assetIds.push(_erc1155TokenId);
            ERC721TokenAsset memory newerc721 = ERC721TokenAsset(
                _erc721Tokens[i],
                _erc1155TokenId,
                address(0),
                _paymentPerFrequency[i],
                block.timestamp
            );
            erc721TokenAssets.push(newerc721);
            amounts[i] = 1;
            _orderBook[manager][_erc1155TokenId] = 1;
            _erc721Tokens[i].transferFrom(
                manager,
                address(this),
                _erc1155TokenId
            );
        }

        mintBatch(erc721assetIds, amounts, _data);

        emit OrderBatch(manager, erc721assetIds, amounts);
    }

    function getTargetDeposit(uint256 _id)
        external
        view
        onlyManager
        returns (uint256)
    {
        return _orderBook[manager][_id];
    }

    function withdrawERC20Assets() internal {
        uint256[] memory paidAmounts = new uint256[](erc20TokenAssets.length);
        uint256 CountOfPaidAmounts = 0;
        for (uint256 i = 0; i < erc20TokenAssets.length; i++) {
            if (
                erc20TokenAssets[i].erc20TokenId == 0 ||
                block.number >= erc20TokenAssets[i].lockedUntil
            ) {
                continue;
            }

            erc20TokenAssets[i].erc20TokenAmount -= erc20TokenAssets[i]
                .erc20PaymentPerFrequency;
            if (erc20TokenAssets[i].erc20TokenAmount <= 0) {
                erc20TokenAssets[i].erc20TokenId = 0;
            }

            _orderBook[manager][
                erc20TokenAssets[i].erc20TokenId
            ] -= erc20TokenAssets[i].erc20PaymentPerFrequency;

            paidAmounts[CountOfPaidAmounts] = erc20TokenAssets[i]
                .erc20PaymentPerFrequency;

            CountOfPaidAmounts++;

            erc20TokenAssets[i].erc20.transfer(
                beneficiary,
                erc20TokenAssets[i].erc20PaymentPerFrequency
            );
        }
        _burnBatch(msg.sender, erc20assetIds, paidAmounts);

        emit PayToBeneficiary(erc20assetIds, paidAmounts);
    }

    function withdrawERC721Assets() internal {
        uint256[] memory paidAmounts = new uint256[](erc721TokenAssets.length);
        uint256 CountOfPaidAmounts = 0;
        for (uint256 i = 0; i < erc721TokenAssets.length; i++) {
            
            if (
                erc721TokenAssets[i].erc721TokenId == 0 ||
                block.number >= erc20TokenAssets[i].lockedUntil
            ) {
                continue;
            }

            erc721TokenAssets[i].erc721TokenId == 0;

            _orderBook[msg.sender][erc721TokenAssets[i].erc721TokenId] = 0;
            paidAmounts[CountOfPaidAmounts] = 1;
            CountOfPaidAmounts++;
            erc721TokenAssets[i].erc721.transferFrom(
                address(this),
                beneficiary,
                erc721TokenAssets[i].erc721TokenId
            );
        }
        _burnBatch(msg.sender, erc721assetIds, paidAmounts);
        emit PayToBeneficiary(erc721assetIds, paidAmounts);
    }

    function updateBasisPoint(uint256 _basepoint) external onlyManager {
        basisPoint = _basepoint;
        emit UpdateBasisPoint(basisPoint);
    }

    function paySemiAnnualFeeForFirstTwoYear(bool hasPromoter, address _target)
        external
        onlyManager
    {
        require(subscription.isTwoYear);
        require(block.timestamp >= subscription.nextPayment, "not due yet");
        uint256 semiAnnualFee = 0;
        uint256 tokenId = 0;
        if (hasPromoter) {
            tokenId = PrToken;
        } else {
            tokenId = DToken;
        }
        semiAnnualFee = _orderBook[_target][tokenId] * (basisPoint / 100);
        tokenSupply[tokenId] += semiAnnualFee;
        _AnualFeeTotal += semiAnnualFee;

        emit PaymentSentForFirstTwoYear(
            _target,
            tokenId,
            semiAnnualFee,
            _AnualFeeTotal,
            block.timestamp
        );

        subscription.nextPayment += payAnnualFrequency;
        subscription.isTwoYear = false;
    }

    function paySemiAnnualFeeForSubsequentYear(address _target)
        external
        onlyManager
    {
        require(!subscription.isTwoYear);
        require(block.timestamp >= subscription.nextPayment, "not due yet");
        uint256 semiAnnualFee = 0;
        semiAnnualFee = _orderBook[_target][DToken] * (basisPoint / 100);
        tokenSupply[DToken] += semiAnnualFee;
        _AnualFeeTotal += semiAnnualFee;

        emit PaymentSentForSubsequentYear(
            _target,
            semiAnnualFee,
            _AnualFeeTotal,
            block.timestamp
        );

        subscription.nextPayment += payAnnualFrequency;
    }

    function getSpecificPrToken(string memory _prTokenKey)
        external
        view
        returns (string memory)
    {
        uint256 prTokenLength = prTokens.length;
        for (uint256 i = 0; i < prTokenLength; i++) {
            if (
                keccak256(abi.encodePacked(prTokens[i].tokenKey)) ==
                keccak256(abi.encodePacked(_prTokenKey))
            ) {
                return getURI(dTrustUri, i);
            }
        }
        return "";
    }

    function getCountOfPrToken() external view returns (uint256) {
        return prTokens.length;
    }

    function getCurrentPrToken() external view returns (uint256) {
        PrTokenStruct memory currentPrToken = prTokens[prTokens.length - 1];
        return currentPrToken.id;
    }

    function process() internal {
        withdrawERC20Assets();
        withdrawERC721Assets();
        schedule();
    }

    function schedule() internal {
        for (uint256 i = 0; i < erc20TokenAssets.length; i++) {
            erc20TokenAssets[i].lockedUntil =
                block.timestamp +
                erc20TokenAssets[i].paymentInterval;
            erc20TokenAssets[i].currentScheduledTransaction = scheduler
                .schedule(
                    address(this),
                    "",
                    [
                        1000000,
                        0,
                        255,
                        erc20TokenAssets[i].lockedUntil,
                        20000000000 wei,
                        20000000000 wei,
                        20000000000 wei,
                        30000000000 wei
                    ]
                );
        }

        for (uint256 i = 0; i < erc721TokenAssets.length; i++) {
            erc721TokenAssets[i].lockedUntil =
                block.timestamp +
                erc721TokenAssets[i].paymentInterval;
            erc721TokenAssets[i].currentScheduledTransaction = scheduler
                .schedule(
                    address(this),
                    "",
                    [
                        1000000,
                        0,
                        255,
                        erc721TokenAssets[i].lockedUntil,
                        20000000000 wei,
                        20000000000 wei,
                        20000000000 wei,
                        30000000000 wei
                    ]
                );
        }

        emit PaymentScheduled(erc20TokenAssets, erc721TokenAssets, beneficiary);
    }

    function _tokenHash(IMyERC721 erc721token)
        internal
        virtual
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(erc721token)));
    }
}
