// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import "forge-std/console2.sol";

import { IERC20 } from "openzeppelin/token/ERC20/IERC20.sol";
import { E, SD59x18, sd, toSD59x18, fromSD59x18 } from "prb-math/SD59x18.sol";
import { UD60x18, ud, fromUD60x18 } from "prb-math/UD60x18.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { SD1x18 } from "prb-math/SD1x18.sol";

// import { TwabController } from "./interfaces/TwabController.sol";
import { TwabController } from "v5-twab-controller/TwabController.sol";

import { DrawAccumulatorLib } from "./libraries/DrawAccumulatorLib.sol";
import { TierCalculationLib } from "./libraries/TierCalculationLib.sol";

contract PrizePool {

    /// @notice Draw struct created every draw
    /// @param winningRandomNumber The random number returned from the RNG service
    /// @param drawId The monotonically increasing drawId for each draw
    /// @param timestamp Unix timestamp of the draw. Recorded when the draw is created by the DrawBeacon.
    /// @param beaconPeriodStartedAt Unix timestamp of when the draw started
    /// @param beaconPeriodSeconds Unix timestamp of the beacon draw period for this draw.
    struct Draw {
        uint256 winningRandomNumber;
        uint32 drawId;
        uint64 timestamp;
        uint64 beaconPeriodStartedAt;
        uint32 beaconPeriodSeconds;
    }

    struct ClaimRecord {
        uint32 drawId;
        uint224 amount;
    }

    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS;
    uint32 immutable internal ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS;

    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_2_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_3_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_4_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_5_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_6_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_7_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_8_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_9_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_10_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_11_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_12_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_13_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_14_TIERS;
    uint32 immutable internal CANARY_PRIZE_COUNT_FOR_15_TIERS;

    mapping(address => DrawAccumulatorLib.Accumulator) internal vaultAccumulators;

    DrawAccumulatorLib.Accumulator internal totalAccumulator;

    // tier number => tier exchange rate is prizeToken per share
    mapping(uint256 => UD60x18) internal _tierExchangeRates;

    mapping(address => ClaimRecord) internal claimRecords;

    // 160 bits
    IERC20 public immutable prizeToken;

    // 64 bits
    SD1x18 public immutable alpha;

    uint32 public immutable grandPrizePeriodDraws;

    TwabController public immutable twabController;

    uint96 public immutable tierShares;

    uint32 public immutable drawPeriodSeconds;

    // percentage of prizes that must be claimed to bump the number of tiers
    // 64 bits
    UD2x18 public immutable claimExpansionThreshold;

    uint96 public immutable canaryShares;
    uint96 public immutable reserveShares;

    uint256 internal _internalBalance;

    UD60x18 internal _prizeTokenPerShare;

    uint256 public reserve;

    uint256 winningRandomNumber;

    uint8 public numberOfTiers;
    uint32 claimCount;
    uint32 canaryClaimCount;

    uint32 drawId;
    uint64 drawStartedAt;

    // TODO: add requires
    constructor (
        IERC20 _prizeToken,
        TwabController _twabController,
        uint32 _grandPrizePeriodDraws,
        uint32 _drawPeriodSeconds,
        uint64 _drawStartedAt,
        uint8 _numberOfTiers,
        uint96 _tierShares,
        uint96 _canaryShares,
        uint96 _reserveShares,
        UD2x18 _claimExpansionThreshold,
        SD1x18 _alpha
    ) {
        prizeToken = _prizeToken;
        twabController = _twabController;
        grandPrizePeriodDraws = _grandPrizePeriodDraws;
        numberOfTiers = _numberOfTiers;
        tierShares = _tierShares;
        canaryShares = _canaryShares;
        reserveShares = _reserveShares;
        alpha = _alpha;
        claimExpansionThreshold = _claimExpansionThreshold;
        drawPeriodSeconds = _drawPeriodSeconds;
        drawStartedAt = _drawStartedAt;

        require(numberOfTiers > 1, "num-tiers-gt-1");

        ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS = TierCalculationLib.estimatedClaimCount(2, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS = TierCalculationLib.estimatedClaimCount(3, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS = TierCalculationLib.estimatedClaimCount(4, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS = TierCalculationLib.estimatedClaimCount(5, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS = TierCalculationLib.estimatedClaimCount(6, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS = TierCalculationLib.estimatedClaimCount(7, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS = TierCalculationLib.estimatedClaimCount(8, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS = TierCalculationLib.estimatedClaimCount(9, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS = TierCalculationLib.estimatedClaimCount(10, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS = TierCalculationLib.estimatedClaimCount(11, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS = TierCalculationLib.estimatedClaimCount(12, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS = TierCalculationLib.estimatedClaimCount(13, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS = TierCalculationLib.estimatedClaimCount(14, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS = TierCalculationLib.estimatedClaimCount(15, _grandPrizePeriodDraws);
        ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS = TierCalculationLib.estimatedClaimCount(16, _grandPrizePeriodDraws);

        CANARY_PRIZE_COUNT_FOR_2_TIERS = uint32(TierCalculationLib.canaryPrizeCount(2, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_3_TIERS = uint32(TierCalculationLib.canaryPrizeCount(3, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_4_TIERS = uint32(TierCalculationLib.canaryPrizeCount(4, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_5_TIERS = uint32(TierCalculationLib.canaryPrizeCount(5, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_6_TIERS = uint32(TierCalculationLib.canaryPrizeCount(6, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_7_TIERS = uint32(TierCalculationLib.canaryPrizeCount(7, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_8_TIERS = uint32(TierCalculationLib.canaryPrizeCount(8, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_9_TIERS = uint32(TierCalculationLib.canaryPrizeCount(9, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_10_TIERS = uint32(TierCalculationLib.canaryPrizeCount(10, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_11_TIERS = uint32(TierCalculationLib.canaryPrizeCount(11, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_12_TIERS = uint32(TierCalculationLib.canaryPrizeCount(12, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_13_TIERS = uint32(TierCalculationLib.canaryPrizeCount(13, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_14_TIERS = uint32(TierCalculationLib.canaryPrizeCount(14, _canaryShares, _reserveShares, _tierShares));
        CANARY_PRIZE_COUNT_FOR_15_TIERS = uint32(TierCalculationLib.canaryPrizeCount(15, _canaryShares, _reserveShares, _tierShares));
    }

    // TODO: see if we can transfer via a callback from the liquidator and add events
    function contributePrizeTokens(address _prizeVault, uint256 _amount) external returns(uint256) {
        // how do we know how many new tokens there are?
        uint256 _deltaBalance = prizeToken.balanceOf(address(this)) - _internalBalance;

        require(_deltaBalance >=  _amount, "PP/deltaBalance-gte-amount");

        _internalBalance += _amount;

        DrawAccumulatorLib.add(vaultAccumulators[_prizeVault], _amount, drawId + 1, SD1x18.intoSD59x18(alpha));
        DrawAccumulatorLib.add(totalAccumulator, _amount, drawId + 1, alpha);

        return _deltaBalance;
    }

    function getNextDrawId() external view returns (uint256) {
        return uint256(drawId) + 1;
    }

    function prizeTokenPerShare() external view returns (uint256) {
        return UD60x18.unwrap(_prizeTokenPerShare);
    }

    // TODO: add event
    function setDraw(Draw calldata _nextDraw) external returns (Draw memory) {
        (UD60x18 deltaExchangeRate, uint256 remainder) = TierCalculationLib.computeNextExchangeRateDelta(_getTotalShares(numberOfTiers), DrawAccumulatorLib.getAvailableAt(totalAccumulator, drawId + 1, alpha));
        _prizeTokenPerShare = ud(UD60x18.unwrap(_prizeTokenPerShare) + UD60x18.unwrap(deltaExchangeRate));
        reserve += remainder;
        require(_nextDraw.drawId == drawId + 1, "not next draw");
        claimCount = 0;
        canaryClaimCount = 0;
        return _nextDraw;
    }

    function claimPrize(
        address _vault,
        address _user,
        uint8 _tier
    ) external returns (uint256) {
        return _claimPrize(_vault, _user, _tier);
    }

    function _claimPrize(
        address _vault,
        address _user,
        uint8 _tier
    ) internal returns (uint256) {
        uint256 prizeSize;
        if (isWinner(_vault, _user, _tier)) {
            // transfer prize to user
            prizeSize = calculatePrizeSize(_tier);
        }
        ClaimRecord memory claimRecord = claimRecords[_user];
        uint32 drawId = drawId;
        uint256 payout = prizeSize;
        if (payout > 0 && claimRecord.drawId == drawId) {
            if (claimRecord.amount >= payout) {
                revert("already claimed");
            } else {
                payout -= claimRecord.amount;
            }
        }
        if (payout > 0) {
            // if it's a fresh claim
            if (claimRecord.amount == 0) {
                claimCount++;
            }
            claimRecords[_user] = ClaimRecord({drawId: drawId, amount: uint224(payout + claimRecord.amount)});
            _internalBalance -= prizeSize;
            prizeToken.transfer(_user, prizeSize);
        }
        return payout;
    }

    /**
    * TODO: check that beaconPeriodStartedAt is the timestamp at which the draw started
    * Add in memory start and end timestamp
    */
    function isWinner(
        address _vault,
        address _user,
        uint8 _tier
    ) public returns (bool) {
        require(drawId > 0, "no draw");

        SD59x18 tierOdds = TierCalculationLib.getTierOdds(_tier, numberOfTiers, grandPrizePeriodDraws);
        uint256 drawDuration = TierCalculationLib.estimatePrizeFrequencyInDraws(_tier, numberOfTiers, grandPrizePeriodDraws);
        (uint256 _userTwab, uint256 _vaultTwabTotalSupply) = _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, drawDuration);
        SD59x18 vaultPortion = _getVaultPortion(_vault, drawId, uint32(drawDuration), alpha);
        uint32 tierPrizeCount;
        if (_tier == numberOfTiers) { // then canary tier
            tierPrizeCount = _canaryPrizeCount(_tier);
        } else if (_tier < numberOfTiers) {
            tierPrizeCount = _prizeCount(_tier, numberOfTiers);
        } else {
            return false;
        }
        return TierCalculationLib.isWinner(_user, _tier, _userTwab, _vaultTwabTotalSupply, vaultPortion, tierOdds, tierPrizeCount, winningRandomNumber);
    }

    function _prizeCount(uint8 _tier, uint8 _numberOfTiers) internal view returns (uint32) {
        if (_tier < _numberOfTiers) {
            return uint32(TierCalculationLib.prizeCount(_tier));
        } else if (_tier == _numberOfTiers) {
            return _canaryPrizeCount(_numberOfTiers);
        }
        return 0;
    }

    function _getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) internal returns (uint256 twab, uint256 twabTotalSupply) {
        {
            uint64 endTimestamp = drawStartedAt + drawPeriodSeconds;
            uint64 startTimestamp = uint64(endTimestamp - _drawDuration * drawPeriodSeconds);

            // console2.log("startTimestamp", startTimestamp);
            // console2.log("endTimestamp", endTimestamp);

            twab = twabController.getAverageBalanceBetween(
                _vault,
                _user,
                startTimestamp,
                endTimestamp
            );

            uint64[] memory startTimestamps = new uint64[](1);
            startTimestamps[0] = startTimestamp;
            uint64[] memory endTimestamps = new uint64[](1);
            endTimestamps[0] = endTimestamp;

            uint256[] memory _vaultTwabTotalSupplies = twabController.getAverageTotalSuppliesBetween(
                _vault,
                startTimestamps,
                endTimestamps
            );
            twabTotalSupply = _vaultTwabTotalSupplies[0];
        }
    }

    function getVaultUserBalanceAndTotalSupplyTwab(address _vault, address _user, uint256 _drawDuration) external returns (uint256, uint256) {
        return _getVaultUserBalanceAndTotalSupplyTwab(_vault, _user, _drawDuration);
    }

    function _getVaultPortion(address _vault, uint32 _drawId, uint32 _durationInDraws, SD59x18 _alpha) internal view returns (SD59x18) {
        uint32 _startDrawIdIncluding = uint32(_durationInDraws > _drawId ? 0 : _drawId-_durationInDraws+1);
        uint32 _endDrawIdExcluding = _drawId + 1;
        uint256 vaultContributed = DrawAccumulatorLib.getDisbursedBetween(vaultAccumulators[_vault], _startDrawIdIncluding, _endDrawIdExcluding, _alpha);
        uint256 totalContributed = DrawAccumulatorLib.getDisbursedBetween(totalAccumulator, _startDrawIdIncluding, _endDrawIdExcluding, _alpha);
        if (totalContributed != 0) {
            return sd(int256(vaultContributed)).div(sd(int256(totalContributed)));
        } else {
            return sd(0);
        }
    }

    function getVaultPortion(address _vault, uint32 startDrawId, uint32 endDrawId) external view returns (SD59x18) {
        return _getVaultPortion(_vault, startDrawId, endDrawId, alpha);
    }

    function calculatePrizeSize(uint8 _tier) public view returns (uint256) {
        if (_tier < numberOfTiers) {
            return _getLiquidity(_tier, tierShares) / TierCalculationLib.prizeCount(_tier);
        } else if (_tier == numberOfTiers) { // it's the canary tier
            return _getLiquidity(_tier, canaryShares) / _canaryPrizeCount(_tier);
        } else {
            return 0;
        }
    }

    function getTierLiquidity(uint8 _tier) external view returns (uint256) {
        return _getLiquidity(_tier, tierShares);
    }

    function _getLiquidity(uint8 _tier, uint256 _shares) internal view returns (uint256) {
        UD60x18 _numberOfPrizeTokenPerShareOutstanding = ud(UD60x18.unwrap(_prizeTokenPerShare) - UD60x18.unwrap(_tierExchangeRates[_tier]));

        return fromUD60x18(_numberOfPrizeTokenPerShareOutstanding.mul(UD60x18.wrap(_shares*1e18)));
    }

    function getTotalShares() external view returns (uint256) {
        return _getTotalShares(numberOfTiers);
    }

    function _getTotalShares(uint8 _numberOfTiers) internal view returns (uint256) {
        return _numberOfTiers * tierShares + canaryShares + reserveShares;
    }

    function estimatedPrizeCount() external view returns (uint32) {
        return _estimatedPrizeCount(numberOfTiers);         
    }
    
    function estimatedPrizeCount(uint8 numTiers) external view returns (uint32) {
        return _estimatedPrizeCount(numTiers);
    }

    function canaryPrizeCount(uint8 numTiers) external view returns (uint32) {
        return _canaryPrizeCount(numTiers);
    }

    function _estimatedPrizeCount(uint8 numTiers) internal view returns (uint32) {
        if (numTiers == 2) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_2_TIERS;
        } else if (numTiers == 3) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_3_TIERS;
        } else if (numTiers == 4) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_4_TIERS;
        } else if (numTiers == 5) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_5_TIERS;
        } else if (numTiers == 6) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_6_TIERS;
        } else if (numTiers == 7) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_7_TIERS;
        } else if (numTiers == 8) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_8_TIERS;
        } else if (numTiers == 9) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_9_TIERS;
        } else if (numTiers == 10) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_10_TIERS;
        } else if (numTiers == 11) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_11_TIERS;
        } else if (numTiers == 12) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_12_TIERS;
        } else if (numTiers == 13) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_13_TIERS;
        } else if (numTiers == 14) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_14_TIERS;
        } else if (numTiers == 15) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_15_TIERS;
        } else if (numTiers == 16) {
            return ESTIMATED_PRIZES_PER_DRAW_FOR_16_TIERS;
        }
        return 0;
    }

    function _canaryPrizeCount(uint8 numTiers) internal view returns (uint32) {
        if (numTiers == 2) {
            return CANARY_PRIZE_COUNT_FOR_2_TIERS;
        } else if (numTiers == 3) {
            return CANARY_PRIZE_COUNT_FOR_3_TIERS;
        } else if (numTiers == 4) {
            return CANARY_PRIZE_COUNT_FOR_4_TIERS;
        } else if (numTiers == 5) {
            return CANARY_PRIZE_COUNT_FOR_5_TIERS;
        } else if (numTiers == 6) {
            return CANARY_PRIZE_COUNT_FOR_6_TIERS;
        } else if (numTiers == 7) {
            return CANARY_PRIZE_COUNT_FOR_7_TIERS;
        } else if (numTiers == 8) {
            return CANARY_PRIZE_COUNT_FOR_8_TIERS;
        } else if (numTiers == 9) {
            return CANARY_PRIZE_COUNT_FOR_9_TIERS;
        } else if (numTiers == 10) {
            return CANARY_PRIZE_COUNT_FOR_10_TIERS;
        } else if (numTiers == 11) {
            return CANARY_PRIZE_COUNT_FOR_11_TIERS;
        } else if (numTiers == 12) {
            return CANARY_PRIZE_COUNT_FOR_12_TIERS;
        } else if (numTiers == 13) {
            return CANARY_PRIZE_COUNT_FOR_13_TIERS;
        } else if (numTiers == 14) {
            return CANARY_PRIZE_COUNT_FOR_14_TIERS;
        } else if (numTiers == 15) {
            return CANARY_PRIZE_COUNT_FOR_15_TIERS;
        }
        return 0;
    }

}
