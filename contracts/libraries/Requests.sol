// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./EIP712.sol";

library Requests {
    // keccak256("Request(address maker,address requester,uint256 gameId,uint256 amount,uint256 reserved1,uint256 reserved2)")
    bytes32 public constant REQUEST_TYPEHASH =
        0xd32aee5345fa208c941f81688a0bd6baed57015ace9fce44cfd25c5fb8a5fbf7;

    struct Request {
        address maker;
        address requester;
        uint256 gameId;
        uint256 amount;
        uint256 reserved1;
        uint256 reserved2;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    function hash(Request memory request) internal pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    REQUEST_TYPEHASH,
                    request.maker,
                    request.requester,
                    request.gameId,
                    request.amount,
                    request.reserved1,
                    request.reserved2
                )
            );
    }

    function validate(Request memory request) internal pure {
        require(request.maker != address(0), "invalid maker");
        require(request.requester != address(0), "invalid requester");
        require(request.gameId > 0, "invalid gameId");
        require(request.amount > 0, "invalid amount");
    }

    function verify(Request memory request, bytes32 DOMAIN_SEPARATOR)
        internal pure returns (bool)
    {
        bytes32 hash = request.hash();
        address signer =
            EIP712.recover(
                DOMAIN_SEPARATOR,
                hash,
                request.v,
                request.r,
                request.s
            );
        require(
            signer != address(0) && signer == request.maker,
            "invalid signature"
        );
    }
}