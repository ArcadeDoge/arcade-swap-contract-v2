// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library EIP712 {
    function recover(
        bytes32 DOMAIN_SEPARATOR,
        bytes32 hash,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal pure returns (address) {
        bytes32 digest =
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    DOMAIN_SEPARATOR,
                    hash
                )
            );
        return ecrecover(digest, v, r, s);
    }
}