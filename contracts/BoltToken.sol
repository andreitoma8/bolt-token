// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IRouter.sol";
import "./interfaces/IPoolFactory.sol";
import "./VestingContract.sol";

contract BoltToken is ERC20 {
    IERC20 pool;
    IRouter router;
    IPoolFactory factory;
    VestingContract vestingContract;

    uint256 public constant TOTAL_SUPPLY = 420_690_000_000 * 10 ** 18;
    uint256 public constant LIQUIDITY_ALLOCATION = 63_103_500_000 * 10 ** 18;
    uint256 public constant TEAM_ALLOCATION = 21_034_500_000 * 10 ** 18;
    uint256 public constant DAO_TREASURY_ALLOCATION = 21_034_500_000 * 10 ** 18;
    uint256 public constant AIR_DROP_ALLOCATION = 21_034_500_000 * 10 ** 18;
    uint256 public constant PUBLIC_SALE_ALLOCATION = 294_483_000_000 * 10 ** 18;
    uint256 public constant SOFT_CAP = 25 ether;
    uint256 public constant ETH_FOR_LIQUIDITY = 12.5 ether;

    /**
     * @notice Whether the soft cap has been reached.
     */
    bool public softCapReached;

    /**
     * @notice Whether the sale has ended.
     */
    bool public saleEnded;

    /**
     * @notice The price of the token in wei, with 18 decimals. For example 1 BOLT = 0.0001 ETH, then price = 100000000000000 wei.
     */
    uint256 public price;

    /**
     * @notice The total amount of tokens bought.
     */
    uint256 public totalAmountBought;

    /**
     * @notice The start date of the sale in unix timestamp.
     */
    uint256 public start;

    /**
     * @notice The end date of the sale in unix timestamp.
     */
    uint256 public end;

    /**
     * @notice The date when the liquidity will be unlocked in unix timestamp.
     */
    uint256 public liquidityUnlockDate;

    /**
     * @notice The address of the project wallet/multi-sig.
     */
    address projectWallet;

    /**
     * @notice The amount of tokens bought by each address.
     */
    mapping(address => uint256) public amountBought;

    /**
     * @notice Emits when tokens are bought.
     * @param buyer The address of the buyer.
     * @param amount The amount of tokens bought.
     */
    event TokensBought(address indexed buyer, uint256 amount);

    /**
     * @notice Emits when tokens are claimed.
     * @param claimer The address of the claimer.
     * @param amount The amount of tokens claimed.
     */
    event TokensClaimed(address indexed claimer, uint256 amount);

    /**
     * @notice Emits when ETH is refunded.
     * @param buyer The address of the buyer.
     * @param amount The amount of ETH refunded.
     */
    event EthRefunded(address indexed buyer, uint256 amount);

    /**
     * @notice Emits when the sale is ended.
     * @param totalAmountBought The total amount of tokens bought.
     * @param softCapReached Whether the soft cap has been reached and the sale is successful.
     */
    event SaleEnded(uint256 totalAmountBought, bool softCapReached);

    /**
     * @notice Initializes all the variables, mints the total supply and creates the vesting schedules.
     * @param _price The price of the token in wei, with 18 decimals. For example 1 BOLT = 0.0001 ETH, then price = 100000000000000 wei.
     * @param _start The start date of the sale in unix timestamp.
     * @param _end The end date of the sale in unix timestamp.
     * @param _liquidityUnlockDate The date when the liquidity will be unlocked in unix timestamp.
     * @param _wallets The addresses of the project: 0 = project wallet, 1 = team wallet, 2 = dao treasury wallet, 3 = airdrop wallet.
     * @param _router The address of the router of SyncSwap.
     * @param _factory The address of the pool factory of SyncSwap.
     */
    constructor(
        uint256 _price,
        uint256 _start,
        uint256 _end,
        uint256 _liquidityUnlockDate,
        address[4] memory _wallets,
        IRouter _router,
        IPoolFactory _factory
    ) ERC20("Bolt Token", "BOLT") {
        _mint(address(this), 141982875000 * 10 ** decimals());

        // set up all the variables
        price = _price;
        start = _start;
        end = _end;
        liquidityUnlockDate = _liquidityUnlockDate;
        projectWallet = _wallets[0];
        router = _router;
        factory = _factory;
        vestingContract = new VestingContract(address(this));

        // create the vesting schedules
        _approve(address(this), address(vestingContract), TEAM_ALLOCATION);
        vestingContract.createVestingSchedule(
            _wallets[1], block.timestamp + 6 * 30 days, 10, VestingContract.DurationUnits.Months, TEAM_ALLOCATION
        );
        _approve(address(this), address(vestingContract), DAO_TREASURY_ALLOCATION);
        vestingContract.createVestingSchedule(
            _wallets[2], block.timestamp + 30 days, 10, VestingContract.DurationUnits.Months, DAO_TREASURY_ALLOCATION
        );
        _approve(address(this), address(vestingContract), AIR_DROP_ALLOCATION);
        vestingContract.createVestingSchedule(
            _wallets[3], block.timestamp + 14 days, 0, VestingContract.DurationUnits.Months, AIR_DROP_ALLOCATION
        );
    }

    /**
     * @notice Buys tokens with ETH.
     * @dev The amount of tokens bought is calculated by multiplying the amount of ETH sent by the price.
     */
    function buy() external payable {
        require(block.timestamp >= start, "Sale has not started yet");
        require(block.timestamp <= end, "Sale has ended");
        require(msg.value > 0, "You must send ETH");
        require(!saleEnded, "Sale has ended");

        // compute the amount of tokens to buy
        uint256 amountToBuy = msg.value * 10 ** decimals() / price;

        // update the total amount of tokens bought
        totalAmountBought += amountToBuy;

        // check if the hard cap has been reached
        if (totalAmountBought > PUBLIC_SALE_ALLOCATION) {
            // compute the amount of tokens available to buy and refund the rest
            uint256 availableTokens = PUBLIC_SALE_ALLOCATION - (totalAmountBought - amountToBuy);
            amountToBuy = availableTokens;

            uint256 amountToRefund = msg.value - (amountToBuy * price / 10 ** decimals());

            amountBought[msg.sender] += amountToBuy;

            totalAmountBought = PUBLIC_SALE_ALLOCATION;

            // end the sale
            _endSale();

            (bool sc,) = payable(msg.sender).call{value: amountToRefund}("");
            require(sc, "Refund failed");
        } else {
            // update the amount of tokens bought by the user
            amountBought[msg.sender] += amountToBuy;
        }

        emit TokensBought(msg.sender, amountToBuy);
    }

    /**
     * @notice Claim either the tokens or the ETH depending on whether the soft cap has been reached or not.
     */
    function claim() external {
        require(saleEnded, "Sale has not ended yet");
        require(amountBought[msg.sender] > 0, "You have no tokens to claim");

        // if the soft cap has been reached, send the 25% tokens to the user
        // and lock the other 75% to be vested over 3 weeks, otherwise, refund the user
        if (softCapReached) {
            // compute the amount of tokens bought by the user
            uint256 totalUserAmount = amountBought[msg.sender];
            // reset the amount of tokens bought by the user
            amountBought[msg.sender] = 0;
            // compute the amount of tokens to send
            uint256 amountToSend = totalUserAmount / 4;
            // send the tokens to the user
            _transfer(address(this), msg.sender, amountToSend);
            // copute the amount to vest
            uint256 amountToVest = totalUserAmount - amountToSend;
            // vest the tokens
            _approve(address(this), address(vestingContract), amountToVest);
            vestingContract.createVestingSchedule(
                msg.sender, block.timestamp, 3, VestingContract.DurationUnits.Weeks, amountToVest
            );

            emit TokensClaimed(msg.sender, amountToSend);
        } else {
            // compute the amount of ETH to refund
            uint256 amountToRefund = amountBought[msg.sender] * price / 10 ** decimals();
            // reset the amount of tokens bought by the user
            amountBought[msg.sender] = 0;
            // refund the user
            (bool sc,) = payable(msg.sender).call{value: amountToRefund}("");
            require(sc, "Refund failed");

            emit EthRefunded(msg.sender, amountToRefund);
        }
    }

    /**
     * @notice Ends the sale.
     * @dev If the soft cap has been reached, the liquidity is locked and the tokens are sent to the project wallet.
     */
    function endSale() external {
        require(block.timestamp > end, "Sale has not ended yet");
        require(!saleEnded, "Sale has already ended");

        _endSale();
    }

    /**
     * @notice Unlocks the liquidity after the liquidity unlock date by
     * sends the LP tokens to the project wallet.
     */
    function unlockLiquidity() external {
        require(block.timestamp > liquidityUnlockDate, "Liquidity is still locked");

        uint256 liquidity = pool.balanceOf(address(this));
        pool.transfer(projectWallet, liquidity);
    }

    /**
     * @return The address of the vesting contract
     */
    function getVestingContract() external view returns (address) {
        return address(vestingContract);
    }

    /**
     * @return The address of the pool on SyncSwap
     */
    function getPool() external view returns (address) {
        return address(pool);
    }

    /**
     * @notice Ends the sale.
     */
    function _endSale() internal {
        // mark the sale as ended
        saleEnded = true;

        // if the soft cap has been reached, lock the liquidity and send the tokens to the project wallet
        if (address(this).balance >= SOFT_CAP) {
            softCapReached = true;

            // send the tokens to the project wallet
            uint256 amountToSend = address(this).balance - ETH_FOR_LIQUIDITY;
            (bool sc,) = payable(projectWallet).call{value: amountToSend}("");
            require(sc, "Transfer failed");

            _lockLiquidity();
        }

        emit SaleEnded(totalAmountBought, softCapReached);
    }

    /**
     * @notice Locks the liquidity by first creating a pool and then adding liquidity to it.
     * @dev The pool is created with the BOLT token as the first token and ETH as the second token
     * on the SyncSwap router.
     */
    function _lockLiquidity() internal {
        pool = IERC20(factory.createPool(abi.encode(address(this), address(0))));

        _approve(address(this), address(router), LIQUIDITY_ALLOCATION);

        IRouter.TokenInput[] memory inputs = new IRouter.TokenInput[](2);
        inputs[0] = IRouter.TokenInput({token: address(this), amount: LIQUIDITY_ALLOCATION});
        inputs[1] = IRouter.TokenInput({token: address(0), amount: ETH_FOR_LIQUIDITY});

        router.addLiquidity{value: ETH_FOR_LIQUIDITY}(
            address(pool), inputs, abi.encode(0, 0), 0, address(this), abi.encode(0)
        );
    }
}
