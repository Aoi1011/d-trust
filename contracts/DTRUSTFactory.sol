// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./DTRUST.sol";
import "./ControlKey.sol";

contract DTRUSTFactory {
    struct Token {
        uint256 tokenId;
        string tokenName; // PrToekn, DToken
        string tokenKey;
    }

    DTRUST[] public deployedDTRUSTs;
    uint256 public totalOfControlKeys;
    uint256[] public createdControlKeys;

    function createDTRUST(
        string memory _contractSymbol,
        string memory _newuri,
        string memory _contractName,
        address _settlor,
        address _beneficiary,
        address _trustee
    ) public payable {
        DTRUST newDTRUST = new DTRUST(
            _contractName,
            _contractSymbol,
            _newuri,
            payable(msg.sender),
            payable(_settlor),
            _beneficiary,
            payable(_trustee)
        );
        deployedDTRUSTs.push(newDTRUST);
    }

    function createPromoteToken(
        DTRUST _dtrust,
        string memory _tokenKey
    ) public returns (bool) {
        for (uint256 i = 0; i < deployedDTRUSTs.length; i++) {
            if (deployedDTRUSTs[i] == _dtrust) {
                DTRUST existDTrust = deployedDTRUSTs[i];
                existDTrust.mint(true, 1, _tokenKey);
                return true;
            }
        }
        return false;
    }

    function usePromoteToken(DTRUST _dtrust, string memory _tokenKey)
        public
        view
        returns (string memory)
    {
        for (uint256 i = 0; i < deployedDTRUSTs.length; i++) {
            if (deployedDTRUSTs[i] == _dtrust) {
                DTRUST existDTrust = deployedDTRUSTs[i];
                for (uint256 j = 0; j < existDTrust.getCountOfPrToken(); j++) {
                    if (
                        keccak256(
                            abi.encodePacked(existDTrust.getSpecificTokenKey(j))
                        ) == keccak256(abi.encodePacked(_tokenKey))
                    ) {
                        return existDTrust.getURI(existDTrust.uri(j), j);
                    }
                }
            }
        }
        return "";
    }

    function getAllDeployedDTRUSTs() public view returns (DTRUST[] memory) {
        return deployedDTRUSTs;
    }
}