/// import { _TypedDataEncoder } from "ethers/lib/utils";
import { ethers, network } from "hardhat";
import { _TypedDataEncoder } from "@ethersproject/hash";
import {
  TypedDataDomain,
  TypedDataField,
} from "@ethersproject/abstract-signer";
import { Signature } from "@ethersproject/bytes";

export type RequestType = {
  maker: string;
  requester: string;
  gcToken: string;
  gameId: number;
  amount: string;
  reserved1: number;
  reserved2: number;
};

export type RequestWithSignature = RequestType & {
  v: number;
  r: string;
  s: string;
};

const EIP712DOMAIN_TYPEHASH = ethers.utils.keccak256(
  ethers.utils.toUtf8Bytes(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
  )
);

const getDomainSeparator = (
  name: string,
  version: string,
  chainId: number,
  address: string
) => {
  return ethers.utils.keccak256(
    ethers.utils.defaultAbiCoder.encode(
      ["bytes32", "bytes32", "bytes32", "uint256", "address"],
      [
        EIP712DOMAIN_TYPEHASH,
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(name)),
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(version)),
        chainId,
        address,
      ]
    )
  );
};

class Request {
  // keccak256("Request(address maker,address requester,uint256 gameId,uint256 amount,uint256 reserved1,uint256 reserved2)")
  static REQUEST_TYPEHASH =
    "0xd32aee5345fa208c941f81688a0bd6baed57015ace9fce44cfd25c5fb8a5fbf7";

  public request: RequestType;

  constructor(
    maker: string,
    requester: string,
    gcToken: string,
    gameId: number,
    amount: string
  ) {
    this.request = {
      maker,
      requester,
      gcToken,
      gameId,
      amount,
      reserved1: 0,
      reserved2: 0,
    };
  }

  hash(overrides?: RequestType) {
    return ethers.utils.keccak256(
      ethers.utils.defaultAbiCoder.encode(
        [
          "bytes32",
          "address",
          "address",
          "address",
          "uint256",
          "uint256",
          "uint256",
          "uint256",
        ],
        [
          Request.REQUEST_TYPEHASH,
          overrides?.maker || this.request.maker,
          overrides?.requester || this.request.requester,
          overrides?.gcToken || this.request.gcToken,
          overrides?.gameId || this.request.gameId,
          overrides?.amount || this.request.amount,
          overrides?.reserved1 || this.request.reserved1,
          overrides?.reserved2 || this.request.reserved2,
        ]
      )
    );
  }

  async sign(
    verifyingContract: string,
    overrides?: RequestType
  ): Promise<Signature> {
    const chainId = network.config.chainId ?? 33177;
    const DOMAIN_SEPARATOR = getDomainSeparator(
      "ArcadeSwap",
      "1",
      chainId,
      verifyingContract
    );
    const digest = ethers.utils.keccak256(
      ethers.utils.solidityPack(
        ["bytes1", "bytes1", "bytes32", "bytes32"],
        ["0x19", "0x01", DOMAIN_SEPARATOR, this.hash()]
      )
    );

    // const domain: TypedDataDomain = {
    //   name: "AradeSwap",
    //   version: "1",
    //   chainId,
    //   verifyingContract,
    // };
    // const types: Record<string, TypedDataField[]> = {
    //   // EIP712Domain: [
    //   //   { name: "name", type: "string" },
    //   //   { name: "version", type: "string" },
    //   //   { name: "chainId", type: "uint256" },
    //   //   { name: "verifyingContract", type: "address" },
    //   // ],
    //   Request: [
    //     { name: "maker", type: "address" },
    //     { name: "requester", type: "address" },
    //     { name: "gcToken", type: "address" },
    //     { name: "gameId", type: "uint256" },
    //     { name: "amount", type: "uint256" },
    //     { name: "reserved1", type: "uint256" },
    //     { name: "reserved2", type: "uint256" },
    //   ],
    // };
    // const value: Record<string, any> = {
    //   maker: overrides?.maker || this.request.maker,
    //   requester: overrides?.requester || this.request.requester,
    //   gcToken: overrides?.gcToken || this.request.gcToken,
    //   gameId: overrides?.gameId || this.request.gameId,
    //   amount: overrides?.amount || this.request.amount,
    //   reserved1: overrides?.reserved1 || this.request.reserved1,
    //   reserved2: overrides?.reserved2 || this.request.reserved2,
    // };

    // const digest = _TypedDataEncoder.encode(domain, types, value);
    const privateKey =
      "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";
    const key = new ethers.utils.SigningKey(ethers.utils.hexlify(privateKey));
    const signDigest = key.signDigest.bind(key);
    const signature = ethers.utils.joinSignature(signDigest(digest));

    // const signature: Signature = key.signDigest(digest);
    return ethers.utils.splitSignature(signature);
  }
}

export default Request;
