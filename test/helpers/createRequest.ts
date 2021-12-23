import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber, Signature, Transaction } from "ethers";
import Request from "./Request";

export const createBuyRequest = async (
  signer: SignerWithAddress,
  requester: SignerWithAddress,
  gcToken: string,
  gameId: number,
  amount: BigNumber,
  reserved1: BigNumber,
  reserved2: BigNumber,
  verifyingContract: string
): Promise<Signature> => {
  const request: Request = new Request(
    signer.address,
    requester.address,
    gcToken,
    gameId,
    amount.toString()
  );
  return await request.sign(verifyingContract);
};

export const createSellRequest = async () => {};
