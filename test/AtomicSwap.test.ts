import {
    time,
    loadFixture,
} from "@nomicfoundation/hardhat-toolbox/network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import hre from "hardhat";
import { AtomicSwap } from "../typechain-types";

const SwapperTypes = {
    Swap: [
        { name: 'ownerA', type: 'address'},
        { name: 'ownerB', type: 'address'},
        { name: 'tokenA', type: 'address'},
        { name: 'tokenB', type: 'address'},
        { name: 'valueA', type: 'uint256'},
        { name: 'valueB', type: 'uint256'},
        { name: 'nonceOwnerA', type: 'uint256'},
        { name: 'nonceOwnerB', type: 'uint256'},
        { name: 'deadline', type: 'uint256'},
    ]
};

describe("AtomicSwap", function () {

    async function deploySwapFixture() {

        // Contracts are deployed using the first signer/account by default
        const [owner, bob, alice] = await hre.ethers.getSigners();

        const AtomicSwap = await hre.ethers.getContractFactory("AtomicSwap");
        const Token = await hre.ethers.getContractFactory("Token");

        const swapper = await AtomicSwap.deploy("SwapperDomain");
        const tokenA = await Token.deploy("TokenA", "TKA", hre.ethers.parseEther("1000"), { from: owner.address })
        const tokenB = await Token.deploy("TokenB", "TKB", hre.ethers.parseEther("1000"), { from: owner.address })
        const d = await swapper.eip712Domain()
        const domain = { name: d.name, version: d.version, chainId: d.chainId, verifyingContract: d.verifyingContract}

        return { swapper, tokenA, tokenB, bob, alice, owner, domain };
    }

    describe('constructor()', function() {
        it('should deploy', async function() {
            const { swapper } = await loadFixture(deploySwapFixture);
            expect((await swapper.eip712Domain()).name).to.equal("SwapperDomain")
        })
    })

    describe('swap(Swap memory swap, Sig memory sigA, Sig memory sigB)', function() {
        it('should revert if deadline not met')
        it('should revert if nonces are wrong')
        it('should revert if either signatures are wrong')
        it('should revert on reentrancy')
        it('should swap on correct signatures', async function() {
            const { swapper, owner, tokenA, tokenB, bob, alice, domain } = await loadFixture(deploySwapFixture);
            
            tokenA.transfer(bob, hre.ethers.parseEther("100"), { from: owner })
            tokenA.approve(await swapper.getAddress(), hre.ethers.parseEther("100"), { from: bob})
            
            tokenB.transfer(alice, hre.ethers.parseEther("100"), { from: owner })
            tokenB.approve(await swapper.getAddress(), hre.ethers.parseEther("100"), { from: alice})

            const swapOffer = {
                ownerA: bob.address,
                ownerB: alice.address, 
                tokenA: await tokenA.getAddress(),
                tokenB: await tokenB.getAddress(),
                valueA: hre.ethers.parseEther("10"),
                valueB: hre.ethers.parseEther("5"),
                nonceOwnerA: await swapper.nonces(bob.address),
                nonceOwnerB: await swapper.nonces(alice.address),
                deadline: 100 + await hre.ethers.provider.getBlockNumber() 
            }

            const sigA = await bob.signTypedData(
                domain,
                SwapperTypes,
                swapOffer )
            
            const sigB = await bob.signTypedData(
                domain,
                SwapperTypes,
                swapOffer )
            
            const tx = swapper.run(swapOffer, sigA, sigB)
            expect(tx).to.changeTokenBalances(tokenA, [bob, alice], [-10, 10])
            expect(tx).to.changeTokenBalances(tokenB, [bob, alice], [-5, 5])
        })
    })
})