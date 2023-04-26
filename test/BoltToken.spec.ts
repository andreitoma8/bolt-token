import type { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import chai, { expect } from "chai";
import chaiAsPromised from "chai-as-promised";
import { ethers } from "hardhat";

import { BoltToken, MockSwap, VestingContract } from "../typechain-types";

chai.use(chaiAsPromised);

describe("Bolt ICO and Vesting", function () {
    let bolt: BoltToken;
    let swap: any;
    let vesting: VestingContract;

    let deployer: SignerWithAddress;
    let teamWallet: SignerWithAddress;
    let daoWallet: SignerWithAddress;
    let airdropWallet: SignerWithAddress;

    let alice: SignerWithAddress;
    let bob: SignerWithAddress;
    let carol: SignerWithAddress;

    let startTime: number;
    let endTime: number;
    let liquidityUnlcokDate: number;

    const totalSupply = ethers.utils.parseEther("420690000000");
    const publicSaleAllocation = ethers.utils.parseEther("294483000000");
    const liquidityAllocation = ethers.utils.parseEther("63103500000");
    const teamAllocation = ethers.utils.parseEther("21034500000");

    const increaseTime = async (seconds: number) => {
        await ethers.provider.send("evm_increaseTime", [seconds]);
        await ethers.provider.send("evm_mine", []);
    };

    before(async function () {
        [deployer, teamWallet, daoWallet, airdropWallet, alice, bob, carol] = await ethers.getSigners();
    });


    beforeEach(async function () {
        const MockSwap = await ethers.getContractFactory("MockSwap");
        swap = (await MockSwap.deploy()) as MockSwap;

        startTime = (await ethers.provider.getBlock("latest")).timestamp + 60;
        endTime = startTime + 60 * 60 * 24;
        liquidityUnlcokDate = endTime + 60 * 60 * 24;

        const BoltToken = await ethers.getContractFactory("BoltToken");
        bolt = (await BoltToken.deploy(startTime, endTime, liquidityUnlcokDate, [deployer.address, teamWallet.address, daoWallet.address, airdropWallet.address], swap.address, swap.address)) as BoltToken;

        vesting = await ethers.getContractAt("VestingContract", await bolt.getVestingContract()) as VestingContract;
    });

    describe("BoltToken", function () {
        it("should be correctly deployed", async function () {
            expect(await bolt.totalSupply()).to.equal(ethers.utils.parseEther("420690000000"));
            expect(await bolt.start()).to.equal(startTime);
            expect(await bolt.end()).to.equal(endTime);
            expect(await bolt.liquidityUnlockDate()).to.equal(liquidityUnlcokDate);
        });

        it("should initialize vesting correctly", async function () {
            expect(await bolt.initializeVesting()).to.changeTokenBalance(bolt, vesting.address, totalSupply.sub(publicSaleAllocation));

            const vestingScheduleTeam = await vesting.vestingSchedules(teamWallet.address, 0);
            expect(vestingScheduleTeam.amountTotal).to.equal(teamAllocation);
        });

        it("should not allow to initialize vesting twice", async function () {
            await bolt.initializeVesting();
            await expect(bolt.initializeVesting()).to.be.revertedWith("Initializable: contract is already initialized");
        });

        describe("buy", function () {
            it("should revert if not started", async function () {
                await expect(bolt.connect(alice).buy()).to.be.revertedWith("Sale has not started yet");
            });

            it("should revert if ended", async function () {
                await increaseTime(60 * 60 * 24 + 61);
                await expect(bolt.connect(alice).buy()).to.be.revertedWith("Sale has ended");
            });

            it("should revert if amount is 0", async function () {
                await increaseTime(60);
                await expect(bolt.connect(alice).buy({ value: 0 })).to.be.revertedWith("Amount must be greater than 0");
            });

            it("should correctly buy tokens", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("0.2") });

                expect(await bolt.amountBought(alice.address)).to.equal(ethers.utils.parseEther("0.2").mul(ethers.utils.parseEther("1")).div(await bolt.PRICE()));
            });
        });

        describe("claim", function () {
            it("should revert if the user has not bought any tokens", async function () {
                await expect(bolt.connect(alice).claim()).to.be.revertedWith("You have no tokens to claim");
            });

            it("should revert if the sale has not ended", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("0.2") });

                await expect(bolt.connect(alice).claim()).to.be.revertedWith("Sale has not ended yet");
            });

            it("should correctly claim ETH", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("0.2") });
                await increaseTime(60 * 60 * 24 + 1);

                await bolt.endSale();

                await expect(bolt.connect(alice).claim()).to.changeEtherBalance(alice, ethers.utils.parseEther("0.2").sub(1));
            });

            it("should correctly claim tokens", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("10") });
                await bolt.connect(bob).buy({ value: ethers.utils.parseEther("10") });
                await bolt.connect(carol).buy({ value: ethers.utils.parseEther("10") });
                await increaseTime(60 * 60 * 24 + 1);

                await bolt.endSale();

                await bolt.connect(alice).claim();

                const totalTokensBoughtAlice = ethers.utils.parseEther("10").mul(ethers.utils.parseEther("1")).div(await bolt.PRICE());
                const tokensToBeSentAlice = totalTokensBoughtAlice.div(4);
                const tokensToBeVestedAlice = totalTokensBoughtAlice.sub(tokensToBeSentAlice);

                expect(await bolt.balanceOf(alice.address)).to.equal(tokensToBeSentAlice);

                const aliceVentingSchedule = await vesting.vestingSchedules(alice.address, 0);
                expect(aliceVentingSchedule.amountTotal).to.equal(tokensToBeVestedAlice);
            });
        });

        describe("endSale", function () {
            it("should revert if the sale has not ended", async function () {
                await expect(bolt.endSale()).to.be.revertedWith("Sale has not ended yet");
            });

            it("should revert if the sale has already ended", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("0.2") });
                await increaseTime(60 * 60 * 24 + 1);

                await bolt.endSale();

                await expect(bolt.endSale()).to.be.revertedWith("Sale has already ended");
            });

            it("should correctly end the sale", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("0.2") });
                await increaseTime(60 * 60 * 24 + 1);

                await expect(bolt.endSale()).to.emit(bolt, "SaleEnded");
                expect(await bolt.saleEnded()).to.be.true;
            });

            it("should correctly send ETH to the team wallet", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("30") });
                await increaseTime(60 * 60 * 24 + 1);

                await expect(bolt.endSale()).to.changeEtherBalance(deployer, ethers.utils.parseEther("17.5"));
            });

            it("should correctly add liquidity", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("30") });
                await increaseTime(60 * 60 * 24 + 1);

                await expect(bolt.endSale()).to.changeTokenBalance(bolt, swap, liquidityAllocation);
                expect(await swap.balanceOf(bolt.address)).to.equal(ethers.utils.parseEther("100"));
            });
        });

        describe("unlockLiquidity", function () {
            it("should revert if the liquidity is still locked", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("30") });
                await increaseTime(60 * 60 * 24 + 1);
                await bolt.endSale();

                await expect(bolt.unlockLiquidity()).to.be.revertedWith("Liquidity is still locked");
            });

            it("should correctly unlock liquidity", async function () {
                await increaseTime(60);
                await bolt.connect(alice).buy({ value: ethers.utils.parseEther("30") });
                await increaseTime(60 * 60 * 24 + 1);
                await bolt.endSale();
                await increaseTime(60 * 60 * 24 * 30 + 1);

                await expect(bolt.unlockLiquidity()).to.emit(bolt, "LiquidityUnlocked");
                expect(await swap.balanceOf(deployer.address)).to.equal(ethers.utils.parseEther("100"));
            });
        });
    });
});
