// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.13;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {IFlow} from "./interfaces/IFlow.sol";
import {IGaugeV4} from "./interfaces/IGaugeV4.sol";
import {IVoter} from "./interfaces/IVoter.sol";
import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IRouter} from "./interfaces/IRouter.sol";

/// @title Option Token
/// @notice Option token representing the right to purchase the underlying token
/// at TWAP reduced rate. Similar to call options but with a variable strike
/// price that's always at a certain discount to the market price.
/// @dev Assumes the underlying token and the payment token both use 18 decimals and revert on
// failure to transfer.

contract OptionTokenV3 is ERC20, AccessControl {
    /// -----------------------------------------------------------------------
    /// Constants
    /// -----------------------------------------------------------------------
    uint256 public constant MAX_DISCOUNT = 100; // 100%
    uint256 public constant MIN_DISCOUNT = 0; // 0%
    uint256 public constant MAX_TWAP_POINTS = 50; // 25 hours
    uint256 public constant FULL_LOCK = 52 * 7 * 86400; // 52 weeks
    uint256 public constant MAX_FEES = 50; // 50%

    /// -----------------------------------------------------------------------
    /// Roles
    /// -----------------------------------------------------------------------
    /// @dev The identifier of the role which maintains other roles and settings
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    /// @dev The identifier of the role which is allowed to mint options token
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    /// @dev The identifier of the role which allows accounts to pause execrcising options
    /// in case of emergency
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER");

    /// -----------------------------------------------------------------------
    /// Errors
    /// -----------------------------------------------------------------------
    error OptionToken_PastDeadline();
    error OptionToken_NoAdminRole();
    error OptionToken_NoMinterRole();
    error OptionToken_NoPauserRole();
    error OptionToken_SlippageTooHigh();
    error OptionToken_InvalidDiscount();
    error OptionToken_InvalidLockDuration();
    error OptionToken_InvalidFee();
    error OptionToken_Paused();
    error OptionToken_InvalidTwapPoints();
    error OptionToken_IncorrectPairToken();

    /// -----------------------------------------------------------------------
    /// Events
    /// -----------------------------------------------------------------------

    event Exercise(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount
    );
    event ExerciseVe(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount,
        uint256 nftId
    );
    event ExerciseLp(
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        uint256 paymentAmount,
        uint256 lpAmount
    );
    event SetPairAndPaymentToken(
        IPair indexed newPair,
        address indexed newPaymentToken
    );
    event SetGauge(address indexed newGauge);
    event SetTreasury(address indexed newTreasury,address indexed newVMTreasury);
    event SetFees(uint256 newTeamFee,uint256 newVMFee);
    event SetRouter(address indexed newRouter);
    event SetDiscount(uint256 discount);
    event SetVeDiscount(uint256 veDiscount);
    event SetMinLPDiscount(uint256 lpMinDiscount);
    event SetMaxLPDiscount(uint256 lpMaxDiscount);
    event SetLockDurationForMaxLpDiscount(uint256 lockDurationForMaxLpDiscount);
    event SetLockDurationForMinLpDiscount(uint256 lockDurationForMinLpDiscount);
    event PauseStateChanged(bool isPaused);
    event SetTwapPoints(uint256 twapPoints);

    /// -----------------------------------------------------------------------
    /// Immutable parameters
    /// -----------------------------------------------------------------------

    /// @notice The token paid by the options token holder during redemption
    address public paymentToken;

    /// @notice The underlying token purchased during redemption
    address public immutable underlyingToken;

    /// @notice The voting escrow for locking FLOW to veFLOW
    address public immutable votingEscrow;

    /// @notice The voter contract
    address public immutable voter;



    /// -----------------------------------------------------------------------
    /// Storage variables
    /// -----------------------------------------------------------------------


       /// @notice The router for adding liquidity
    address public router; // this should not be immutable

    /// @notice The pair contract that provides the current TWAP price to purchase
    /// the underlying token while exercising options (the strike price)
    IPair public pair;

    /// @notice The guage contract for the pair
    address public gauge;

    /// @notice The treasury address which receives tokens paid during redemption
    address public treasury;

    /// @notice The VM address which receives tokens paid during redemption
    address public vmTreasury;

    /// @notice the discount given during exercising with locking to the LP
    uint256 public  maxLPDiscount = 20; //  User pays 20%
    uint256 public  minLPDiscount = 80; //  User pays 80%

    /// @notice the discount given during exercising. 30 = user pays 30%
    uint256 public discount = 99; // User pays 90%

    /// @notice the discount for locking to veFLOW
    uint256 public veDiscount = 10; // User pays 10%

    /// @notice the lock duration for max discount to create locked LP
    uint256 public lockDurationForMaxLpDiscount = FULL_LOCK; // 52 weeks

    // @notice the lock duration for max discount to create locked LP
    uint256 public lockDurationForMinLpDiscount = 7 * 86400; // 1 week

    /// @notice
    uint256 public teamFee = 5; // 5%

    /// @notice
    uint256 public vmFee = 5; // 5%

    /// @notice controls the duration of the twap used to calculate the strike price
    // each point represents 30 minutes. 4 points = 2 hours
    uint256 public twapPoints = 4;

    /// @notice Is excersizing options currently paused
    bool public isPaused;

    /// -----------------------------------------------------------------------
    /// Modifiers
    /// -----------------------------------------------------------------------
    /// @dev A modifier which checks that the caller has the admin role.
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert OptionToken_NoAdminRole();
        _;
    }

    /// @dev A modifier which checks that the caller has the admin role.
    modifier onlyMinter() {
        if (
            !hasRole(ADMIN_ROLE, msg.sender) &&
            !hasRole(MINTER_ROLE, msg.sender)
        ) revert OptionToken_NoMinterRole();
        _;
    }

    /// @dev A modifier which checks that the caller has the pause role.
    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender))
            revert OptionToken_NoPauserRole();
        _;
    }

    /// -----------------------------------------------------------------------
    /// Constructor
    /// -----------------------------------------------------------------------

    constructor(
        string memory _name,
        string memory _symbol,
        address _admin,
        address _paymentToken,
        address _underlyingToken,
        IPair _pair,
        address _gaugeFactory,
        address _treasury,
        address _voter,
        address _votingEscrow,
        address _router
    ) ERC20(_name, _symbol, 18) {
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _gaugeFactory);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        paymentToken = _paymentToken;
        underlyingToken = _underlyingToken;
        pair = _pair;
        treasury = _treasury;
        vmTreasury = _treasury;
        voter = _voter;
        votingEscrow = _votingEscrow;
        router = _router;

        emit SetPairAndPaymentToken(_pair, paymentToken);
        emit SetTreasury(_treasury,_treasury);
        emit SetRouter(_router);
    }

    /// -----------------------------------------------------------------------
    /// External functions
    /// -----------------------------------------------------------------------

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param _amount The amount of options tokens to exercise
    /// @param _maxPaymentAmount The maximum acceptable amount to pay. Used for slippage protection.
    /// @param _recipient The recipient of the purchased underlying tokens
    /// @return The amount paid to the treasury to purchase the underlying tokens
    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient
    ) external returns (uint256) {
        return _exercise(_amount, _maxPaymentAmount, _recipient);
    }

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param _amount The amount of options tokens to exercise
    /// @param _maxPaymentAmount The maximum acceptable amount to pay. Used for slippage protection.
    /// @param _recipient The recipient of the purchased underlying tokens
    /// @param _deadline The Unix timestamp (in seconds) after which the call will revert
    /// @return The amount paid to the treasury to purchase the underlying tokens
    function exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _deadline
    ) external returns (uint256) {
        if (block.timestamp > _deadline) revert OptionToken_PastDeadline();
        return _exercise(_amount, _maxPaymentAmount, _recipient);
    }

    /// @notice Exercises options tokens to purchase the underlying tokens.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param _amount The amount of options tokens to exercise
    /// @param _maxPaymentAmount The maximum acceptable amount to pay. Used for slippage protection.
    /// @param _recipient The recipient of the purchased underlying tokens
    /// @param _deadline The Unix timestamp (in seconds) after which the call will revert
    /// @return The amount paid to the treasury to purchase the underlying tokens
    function exerciseVe(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _deadline
    ) external returns (uint256, uint256) {
        if (block.timestamp > _deadline) revert OptionToken_PastDeadline();
        return _exerciseVe(_amount, _maxPaymentAmount, _recipient);
    }

    /// @notice Exercises options tokens to create LP and stake in gauges with lock.
    /// @dev The oracle may revert if it cannot give a secure result.
    /// @param _amount The amount of options tokens to exercise
    /// @param _maxPaymentAmount The maximum acceptable amount to pay. Used for slippage protection.
    /// @param _discount The desired discount
    /// @param _deadline The Unix timestamp (in seconds) after which the call will revert
    /// @return The amount paid to the treasury to purchase the underlying tokens

    function exerciseLp(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient,
        uint256 _discount,
        uint256 _deadline
    ) external returns (uint256, uint256) {
        if (block.timestamp > _deadline) revert OptionToken_PastDeadline();
        return _exerciseLp(_amount, _maxPaymentAmount, _recipient, _discount);
    }

    /// -----------------------------------------------------------------------
    /// Public functions
    /// -----------------------------------------------------------------------

    /// @notice Returns the discounted price in paymentTokens for a given amount of options tokens
    /// @param _amount The amount of options tokens to exercise
    /// @return The amount of payment tokens to pay to purchase the underlying tokens
    function getDiscountedPrice(uint256 _amount) public view returns (uint256) {
        return (getTimeWeightedAveragePrice(_amount) * discount) / 100;
    }

    /// @notice Returns the discounted price in paymentTokens for a given amount of options tokens redeemed to veFLOW
    /// @param _amount The amount of options tokens to exercise
    /// @return The amount of payment tokens to pay to purchase the underlying tokens
    function getVeDiscountedPrice(
        uint256 _amount
    ) public view returns (uint256) {
        return (getTimeWeightedAveragePrice(_amount) * veDiscount) / 100;
    }

    /// @notice Returns the discounted price in paymentTokens for a given amount of options tokens redeemed to veFLOW
    /// @param _amount The amount of options tokens to exercise
    /// @param _discount The discount amount
    /// @return The amount of payment tokens to pay to purchase the underlying tokens
    function getLpDiscountedPrice(
        uint256 _amount,
        uint256 _discount
    ) public view returns (uint256) {
        return (getTimeWeightedAveragePrice(_amount) * _discount) / 100;
    }

    /// @notice Returns the lock duration for a desired discount to create locked LP
    ///
    function getLockDurationForLpDiscount(
        uint256 _discount
    ) public view returns (uint256 duration) {
        (int256 slope, int256 intercept) = getSlopeInterceptForLpDiscount();
        duration = SignedMath.abs(slope * int256(_discount) + intercept);
    }

     // @notice Returns the amount in paymentTokens for a given amount of options tokens required for the LP exercise lp
    /// @param _amount The amount of options tokens to exercise
    /// @param _discount The discount amount
    function getPaymentTokenAmountForExerciseLp(uint256 _amount,uint256 _discount) public view returns (uint256 paymentAmount, uint256 paymentAmountToAddLiquidity)
    {
        paymentAmount = getLpDiscountedPrice(_amount, _discount);
        (uint256 underlyingReserve, uint256 paymentReserve) = IRouter(router).getReserves(underlyingToken, paymentToken, false);
        paymentAmountToAddLiquidity = (_amount * paymentReserve) / underlyingReserve;
    }

    function getSlopeInterceptForLpDiscount()
        public
        view
        returns (int256 slope, int256 intercept)
    {
        slope =
            int256(lockDurationForMaxLpDiscount - lockDurationForMinLpDiscount) /
            (int256(maxLPDiscount) - int256(minLPDiscount));
        intercept = int256(lockDurationForMinLpDiscount) - (slope * int256(minLPDiscount));
    }

    /// @notice Returns the average price in payment tokens over 2 hours for a given amount of underlying tokens
    /// @param _amount The amount of underlying tokens to purchase
    /// @return The amount of payment tokens
    function getTimeWeightedAveragePrice(
        uint256 _amount
    ) public view returns (uint256) {
        uint256[] memory amtsOut = IPair(pair).prices(
            underlyingToken,
            _amount,
            twapPoints
        );
        uint256 len = amtsOut.length;
        uint256 summedAmount;

        for (uint256 i = 0; i < len; i++) {
            summedAmount += amtsOut[i];
        }

        return summedAmount / twapPoints;
    }

    /// -----------------------------------------------------------------------
    /// Admin functions
    /// -----------------------------------------------------------------------

    /// @notice Sets the pair contract. Only callable by the admin.
    /// @param _pair The new pair contract
    function setPairAndPaymentToken(
        IPair _pair,
        address _paymentToken
    ) external onlyAdmin {
        (address token0, address token1) = _pair.tokens();
        if (
            !((token0 == _paymentToken && token1 == underlyingToken) ||
                (token0 == underlyingToken && token1 == _paymentToken))
        ) revert OptionToken_IncorrectPairToken();
        pair = _pair;
        gauge = IVoter(voter).gauges(address(_pair));
        paymentToken = _paymentToken;
        emit SetPairAndPaymentToken(_pair, _paymentToken);
    }

    /// @notice Update gauge address to match with Voter contract
    function updateGauge() external {
        address newGauge = IVoter(voter).gauges(address(pair));
        gauge = newGauge;
        emit SetGauge(newGauge);
    }

    /// @notice Sets the gauge address when the gauge is not listed in Voter. Only callable by the admin.
    /// @param _gauge The new treasury address
    function setGauge(address _gauge) external onlyAdmin {
        gauge = _gauge;
        emit SetGauge(_gauge);
    }

    /// @notice Sets the treasury address. Only callable by the admin.
    /// @param _treasury The new treasury address
    function setTreasury(address _treasury,address _vmTreasury) external onlyAdmin {
        treasury = _treasury;
        vmTreasury = _vmTreasury;
        emit SetTreasury(_treasury,_vmTreasury);
    }

    /// @notice Sets the router address. Only callable by the admin.
    /// @param _router The new router address
    function setRouter(address _router) external onlyAdmin {
        router = _router;
        emit SetRouter(_router);
    }

    /// @notice Sets the team fee. Only callable by the admin.
    /// @param _fee The new team fee.
    /// @param _vmFee The new vm fee.
    function setFees(uint256 _fee,uint256 _vmFee) external onlyAdmin {
        if (_fee + _vmFee > MAX_FEES) revert OptionToken_InvalidFee();
        teamFee = _fee;
        vmFee = _vmFee;
        emit SetFees(_fee,_vmFee);
    }


    /// @notice Sets the discount amount. Only callable by the admin.
    /// @param _discount The new discount amount.
    function setDiscount(uint256 _discount) external onlyAdmin {
        if (_discount > MAX_DISCOUNT || _discount == MIN_DISCOUNT)
            revert OptionToken_InvalidDiscount();
        discount = _discount;
        emit SetDiscount(_discount);
    }

    /// @notice Sets the discount amount for locking. Only callable by the admin.
    /// @param _veDiscount The new discount amount.
    function setVeDiscount(uint256 _veDiscount) external onlyAdmin {
        if (_veDiscount > MAX_DISCOUNT || _veDiscount == MIN_DISCOUNT)
            revert OptionToken_InvalidDiscount();
        veDiscount = _veDiscount;
        emit SetVeDiscount(_veDiscount);
    }

    /// @notice Sets the discount amount for lp. Only callable by the admin.
    /// @param _lpMinDiscount The new discount amount.
    function setMinLPDiscount(uint256 _lpMinDiscount) external onlyAdmin {
        if (_lpMinDiscount > MAX_DISCOUNT || _lpMinDiscount == MIN_DISCOUNT || maxLPDiscount > _lpMinDiscount)
            revert OptionToken_InvalidDiscount();
        minLPDiscount = _lpMinDiscount;
        emit SetMinLPDiscount(_lpMinDiscount);
    }

    /// @notice Sets the discount amount for lp. Only callable by the admin.
    /// @param _lpMaxDiscount The new discount amount.
    function setMaxLPDiscount(uint256 _lpMaxDiscount) external onlyAdmin {
        if (_lpMaxDiscount > MAX_DISCOUNT || _lpMaxDiscount == MIN_DISCOUNT || _lpMaxDiscount > minLPDiscount)
            revert OptionToken_InvalidDiscount();
        maxLPDiscount = _lpMaxDiscount;
        emit SetMaxLPDiscount(_lpMaxDiscount);
    }

    /// @notice Sets the lock duration for max discount amount to create LP and stake in gauge. Only callable by the admin.
    /// @param _duration The new lock duration.
    function setLockDurationForMaxLpDiscount(
        uint256 _duration
    ) external onlyAdmin {
        if (_duration <= lockDurationForMinLpDiscount)
            revert OptionToken_InvalidLockDuration();
        lockDurationForMaxLpDiscount = _duration;
        emit SetLockDurationForMaxLpDiscount(_duration);
    }

    // @notice Sets the lock duration for min discount amount to create LP and stake in gauge. Only callable by the admin.
    /// @param _duration The new lock duration.
    function setLockDurationForMinLpDiscount(
        uint256 _duration
    ) external onlyAdmin {
        if (_duration > lockDurationForMaxLpDiscount)
            revert OptionToken_InvalidLockDuration();
        lockDurationForMinLpDiscount = _duration;
        emit SetLockDurationForMinLpDiscount(_duration);
    }

    /// @notice Sets the twap points. to control the length of our twap
    /// @param _twapPoints The new twap points.
    function setTwapPoints(uint256 _twapPoints) external onlyAdmin {
        if (_twapPoints > MAX_TWAP_POINTS || _twapPoints == 0)
            revert OptionToken_InvalidTwapPoints();
        twapPoints = _twapPoints;
        emit SetTwapPoints(_twapPoints);
    }

    /// @notice Called by the admin to mint options tokens. Admin must grant token approval.
    /// @param _to The address that will receive the minted options tokens
    /// @param _amount The amount of options tokens that will be minted
    function mint(address _to, uint256 _amount) external onlyMinter {
        // transfer underlying tokens from the caller
        _safeTransferFrom(underlyingToken, msg.sender, address(this), _amount);
        // mint options tokens
        _mint(_to, _amount);
    }

    /// @notice Called by the admin to burn options tokens and transfer underlying tokens to the caller.
    /// @param _amount The amount of options tokens that will be burned and underlying tokens transferred to the caller
    function burn(uint256 _amount) external onlyAdmin {
        // transfer underlying tokens to the caller
        _safeTransfer(underlyingToken, msg.sender, _amount);
        // burn option tokens
        _burn(msg.sender, _amount);
    }

    /// @notice called by the admin to re-enable option exercising from a paused state.
    function unPause() external onlyAdmin {
        if (!isPaused) return;
        isPaused = false;
        emit PauseStateChanged(false);
    }

    /// -----------------------------------------------------------------------
    /// Pauser functions
    /// -----------------------------------------------------------------------
    function pause() external onlyPauser {
        if (isPaused) return;
        isPaused = true;
        emit PauseStateChanged(true);
    }

    /// -----------------------------------------------------------------------
    /// Internal functions
    /// -----------------------------------------------------------------------

    function _exercise(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient
    ) internal returns (uint256 paymentAmount) {
        if (isPaused) revert OptionToken_Paused();

        // burn callers tokens
        _burn(msg.sender, _amount);
        paymentAmount = getDiscountedPrice(_amount);
        if (paymentAmount > _maxPaymentAmount)
            revert OptionToken_SlippageTooHigh();

        // transfer team fee to treasury and notify reward amount in gauge
        uint256 gaugeRewardAmount = _takeFees(paymentToken, paymentAmount);
        _usePaymentAsGaugeReward(gaugeRewardAmount);

        // send underlying tokens to recipient
        _safeTransfer(underlyingToken, _recipient, _amount);

        emit Exercise(msg.sender, _recipient, _amount, paymentAmount);
    }

    function _exerciseVe(
        uint256 _amount,
        uint256 _maxPaymentAmount,
        address _recipient
    ) internal returns (uint256 paymentAmount, uint256 nftId) {
        if (isPaused) revert OptionToken_Paused();

        // burn callers tokens
        _burn(msg.sender, _amount);
        paymentAmount = getVeDiscountedPrice(_amount);
        if (paymentAmount > _maxPaymentAmount)
            revert OptionToken_SlippageTooHigh();

        // transfer team fee to treasury and notify reward amount in gauge
        uint256 gaugeRewardAmount = _takeFees(paymentToken, paymentAmount);
        _usePaymentAsGaugeReward(gaugeRewardAmount);

        // lock underlying tokens to veFLOW
        _safeApprove(underlyingToken, votingEscrow, _amount);
        nftId = IVotingEscrow(votingEscrow).create_lock_for(
            _amount,
            FULL_LOCK,
            _recipient
        );

        emit ExerciseVe(msg.sender, _recipient, _amount, paymentAmount, nftId);
    }

    function _exerciseLp(
        uint256 _amount,   // the oTOKEN amount the user wants to redeem with
        uint256 _maxPaymentAmount, // the 
        address _recipient,
        uint256 _discount
    ) internal returns (uint256 paymentAmount, uint256 lpAmount) {
        if (isPaused) revert OptionToken_Paused();
        if (_discount > minLPDiscount || _discount < maxLPDiscount)
            revert OptionToken_InvalidDiscount();

        // burn callers tokens
        _burn(msg.sender, _amount);
        (uint256 paymentAmount,uint256 paymentAmountToAddLiquidity) =  getPaymentTokenAmountForExerciseLp(_amount,_discount);
        if (paymentAmount > _maxPaymentAmount)
            revert OptionToken_SlippageTooHigh();
          
        // Take team fee
        uint256 paymentGaugeRewardAmount = _takeFees(
            paymentToken,
            paymentAmount
        );
        _safeTransferFrom(
            paymentToken,
            msg.sender,
            address(this),
            paymentGaugeRewardAmount + paymentAmountToAddLiquidity
        );

        // Create Lp for users
        _safeApprove(underlyingToken, router, _amount);
        _safeApprove(paymentToken, router, paymentAmountToAddLiquidity);
        (, , lpAmount) = IRouter(router).addLiquidity(
            underlyingToken,
            paymentToken,
            false,
            _amount,
            paymentAmountToAddLiquidity,
            1,
            1,
            address(this),
            block.timestamp
        );

        // Stake the LP in the gauge with lock
        address _gauge = gauge;
        _safeApprove(address(pair), _gauge, lpAmount);
        IGaugeV4(_gauge).depositWithLock(
            _recipient,
            lpAmount,
            getLockDurationForLpDiscount(_discount)
        );

        // notify gauge reward with payment token
        _transferRewardToGauge();

        emit ExerciseLp(
            msg.sender,
            _recipient,
            _amount,
            paymentAmount,
            lpAmount
        );
    }

    function _takeFees(
        address token,
        uint256 paymentAmount
    ) internal returns (uint256 remaining) {
        uint256 _teamFee = (paymentAmount * teamFee) / 100;
        uint256 _vmFee = (paymentAmount * vmFee) / 100;
        _safeTransferFrom(token, msg.sender, treasury, _teamFee);
        _safeTransferFrom(token, msg.sender, vmTreasury, _vmFee);
        remaining = paymentAmount - _teamFee - _vmFee;
    }

    function _usePaymentAsGaugeReward(uint256 amount) internal {
        _safeTransferFrom(paymentToken, msg.sender, address(this), amount);
        _transferRewardToGauge();
    }

    function _transferRewardToGauge() internal {
        uint256 paymentTokenCollectedAmount = IERC20(paymentToken).balanceOf(address(this));

        uint256 leftRewards = IGaugeV4(gauge).left(paymentToken);

        if(paymentTokenCollectedAmount > leftRewards) { // we are sending rewards only if we have more then the current rewards in the gauge
            _safeApprove(paymentToken, gauge, paymentTokenCollectedAmount);
            IGaugeV4(gauge).notifyRewardAmount(paymentToken, paymentTokenCollectedAmount);
        }
    }

    function _safeTransfer(address token, address to, uint256 value) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }

    function _safeApprove(
        address token,
        address spender,
        uint256 value
    ) internal {
        require(token.code.length > 0);
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, value)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
