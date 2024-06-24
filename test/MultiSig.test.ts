import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { AtomicSwap } from "../typechain-types";

const MultiSigTypes = {
    Actions: [
        { name: 'target', type: 'address[]'},
        { name: 'actionType', type: 'uint8[]'},
        { name: 'value', type: 'uint256[]'},
        { name: 'payload', type: 'bytes[]'},
        { name: 'signers', type: 'address[]'},
        { name: 'nonceOfSigner', type: 'uint256[]'},
        { name: 'deadline', type: 'uint256'},
    ]
};

describe("MultiSig", function () {

    async function deployMultisigFixture() {

        // Contracts are deployed using the first signer/account by default
        const [owner, bob, alice, joe] = await hre.ethers.getSigners();

        const MultiSig = await hre.ethers.getContractFactory("MultiSig");

        const multisig = await MultiSig.connect(owner).deploy("MULTISIG_DOMAIN", [bob, alice, joe], 2);
        const d = await multisig.eip712Domain()
        const domain = { name: d.name, version: d.version, chainId: d.chainId, verifyingContract: d.verifyingContract}

        return { multisig, bob, alice, owner, joe, domain };
    }

    describe('constructor()', function() {
        it('should deploy', async function() {
            const { multisig } = await loadFixture(deployMultisigFixture);
            expect((await multisig.eip712Domain()).name).to.equal("MULTISIG_DOMAIN")
        })
    })

    describe('run(Actions memory actions, bytes[] memory signatures)', function() {
        it('should revert if deadline not met')
        it('should revert if minimum signatures not met')
        it('should revert if nonces are wrong')
        it('should revert if either signatures are wrong')
        it('should revert if any duplicate signers')

        it('should revert on reentrancy (due to nonce)')
        it('should revert on reused signature (due to already used nonces)')

        it('should revert on any failed action payload')

        it('should do a call on correct signatures', async function() {
            const { multisig, owner, alice, bob, joe, domain } = await loadFixture(deployMultisigFixture);

            const Token = await hre.ethers.getContractFactory("Token");
            const tokenA = await Token.connect(owner).deploy("TokenA", "TKA", hre.ethers.parseEther("1000"))
            await tokenA.connect(owner).transfer(await multisig.getAddress(), hre.ethers.parseEther("100"))

            const actions = {
                target: [await tokenA.getAddress()],
                actionType: [0], // call
                value: [ hre.ethers.parseEther("0.4")],
                payload: [Token.interface.encodeFunctionData("transfer", [ alice.address, hre.ethers.parseEther("100") ])],
                signers: [alice.address, bob.address],
                nonceOfSigner: await Promise.all([alice.address, bob.address].map(r => multisig.nonces(r))),
                deadline: 10000000000
            }

            const aliceSig = await alice.signTypedData(
                domain,
                MultiSigTypes,
                actions )
            
            const bobSig = await bob.signTypedData(
                domain,
                MultiSigTypes,
                actions)

            const tx = await multisig.connect(owner).run({
                target: actions.target,
                actionType: actions.actionType,
                value: actions.value,
                payload: actions.payload,
                signers: actions.signers,
                deadline: actions.deadline
            }, [bobSig, aliceSig]);
            expect(tx).to.changeTokenBalance(tokenA, [await multisig.getAddress(), alice], [-100, 100])
        })

        it('should do a delegateCall on correct signatures')

        it('should do a staticCall on correct signatures')

        it('should complete multiple actions')

    })
})