// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

contract CrazzzyMonstersStaking is Ownable, IERC721Receiver, ERC721Holder {
    using SafeERC20 for IERC20;

    IERC20 public rewardToken; // ERC20 token used for rewards
    uint256 constant DAY_IN_SECONDS = 60;

    struct NFTCollection {
        mapping(uint256 => uint256) rewardRates; // Mapping from NFT ID to reward rate
    }

    struct StakedNFT {
        address owner; // Address of the NFT owner
        address collection; // Address of the NFT collection contract
        uint256 tokenId; // ID of the NFT
        uint256 stakedAt; // Timestamp when the NFT was staked
        uint256 lastClaimedAt;
        uint256 accumulatedReward;
        bool isHardStake; // Whether it's a hard stake or soft stake
    }

    mapping(address => NFTCollection) private collectionInfo;
    mapping(address => mapping(address => uint256[])) public stakedNFTs;
    mapping(address => mapping(address => mapping(uint256 => StakedNFT)))
        public userStakes;
    mapping(address => StakedNFT[]) public userStakedNFTs;

    // Events
    event NFTStaked(
        address indexed staker,
        address indexed collection,
        uint256 indexed tokenId
    );
    event NFTUnstaked(
        address indexed staker,
        address indexed collection,
        uint256 indexed tokenId
    );
    event RewardClaimed(
        address indexed staker,
        address indexed collection,
        uint256 indexed tokenId,
        uint256 reward
    );

    constructor(address _rewardToken) Ownable(msg.sender) {
        rewardToken = IERC20(_rewardToken);
    }

    // Initialize rewards
    function initializeRewards(
        address collection,
        uint256[] calldata nftIds,
        uint256[] calldata rates
    ) public onlyOwner {
        require(nftIds.length == rates.length, "Invalid input lengths");
        NFTCollection storage nftCollection = collectionInfo[collection];
        for (uint256 i = 0; i < nftIds.length; i++) {
            require(
                nftCollection.rewardRates[nftIds[i]] == 0,
                "Already initialized"
            );
            nftCollection.rewardRates[nftIds[i]] = rates[i];
        }
    }

    // Stake a single NFT
    function stakeNFT(
        address collection,
        uint256 tokenId,
        bool isHardStake
    ) public {
        require(
            !_isNFTStaked(msg.sender, collection, tokenId),
            "NFT is already staked"
        );
        require(
            _isRewardSet(collection, tokenId),
            "No reward set for this collection or tokenID"
        );

        if (isHardStake) {
            IERC721(collection).safeTransferFrom(
                msg.sender,
                address(this),
                tokenId
            );
        }

        StakedNFT memory stakedNFT = StakedNFT(
            msg.sender,
            collection,
            tokenId,
            block.timestamp,
            block.timestamp,
            0,
            isHardStake
        );
        userStakes[msg.sender][collection][tokenId] = stakedNFT;
        userStakedNFTs[msg.sender].push(stakedNFT);

        emit NFTStaked(msg.sender, collection, tokenId);
    }

    // Stake multiple NFTs
    function stakeAllNFTs(
        address collection,
        uint256[] calldata tokenIds,
        bool isHardStake
    ) public {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            stakeNFT(collection, tokenIds[i], isHardStake);
        }
    }

    // Unstake a single NFT
    function unstakeNFT(address collection, uint256 tokenId) public {
        StakedNFT storage stakingInfo = userStakes[msg.sender][collection][
            tokenId
        ];
        require(stakingInfo.owner == msg.sender, "Not owner of NFT");

        uint256 reward = _calculateReward(collection, tokenId, msg.sender);
        stakingInfo.accumulatedReward += reward;

        if (stakingInfo.isHardStake) {
            IERC721(collection).safeTransferFrom(
                address(this),
                msg.sender,
                tokenId
            );
        }

        // Transfer accumulated reward to the user
        rewardToken.safeTransfer(msg.sender, stakingInfo.accumulatedReward);

        delete userStakes[msg.sender][collection][tokenId];
        _removeStakedNFT(msg.sender, collection, tokenId);

        emit NFTUnstaked(msg.sender, collection, tokenId);
    }

    // Unstake all NFTs
    function unstakeAllNFTs() public {
        StakedNFT[] memory stakedNFTsArray = userStakedNFTs[msg.sender];
        for (uint256 i = 0; i < stakedNFTsArray.length; i++) {
            unstakeNFT(
                stakedNFTsArray[i].collection,
                stakedNFTsArray[i].tokenId
            );
        }
    }

    // Claim reward for a single NFT
    function claimReward(address collection, uint256 tokenId) public {
        StakedNFT storage stakingInfo = userStakes[msg.sender][collection][
            tokenId
        ];
        require(stakingInfo.owner == msg.sender, "Not owner of NFT");

        uint256 reward = _calculateReward(collection, tokenId, msg.sender);
        require(reward > 0, "No reward to claim");

        stakingInfo.accumulatedReward += reward;
        stakingInfo.lastClaimedAt = block.timestamp;

        rewardToken.safeTransfer(msg.sender, reward);

        emit RewardClaimed(msg.sender, collection, tokenId, reward);
    }

    // Get total reward for all staked NFTs
    function getTotalRewards() public view returns (uint256) {
        StakedNFT[] memory stakedNFTsArray = userStakedNFTs[msg.sender];
        uint256 totalReward = 0;

        for (uint256 i = 0; i < stakedNFTsArray.length; i++) {
            totalReward += _calculateReward(
                stakedNFTsArray[i].collection,
                stakedNFTsArray[i].tokenId,
                msg.sender
            );
        }

        return totalReward;
    }

    // Helper function to remove staked NFT from array
    function _removeStakedNFT(
        address user,
        address collection,
        uint256 tokenId
    ) internal {
        uint256 length = userStakedNFTs[user].length;
        for (uint256 i = 0; i < length; i++) {
            if (
                userStakedNFTs[user][i].collection == collection &&
                userStakedNFTs[user][i].tokenId == tokenId
            ) {
                userStakedNFTs[user][i] = userStakedNFTs[user][length - 1];
                userStakedNFTs[user].pop();
                break;
            }
        }
    }

    // Check if NFT is already staked
    function _isNFTStaked(
        address staker,
        address collection,
        uint256 tokenId
    ) public view returns (bool) {
        return userStakes[staker][collection][tokenId].owner == staker;
    }

    // Check if reward is set for the NFT
    function _isRewardSet(
        address collection,
        uint256 tokenId
    ) internal view returns (bool) {
        uint256 rewardRate = collectionInfo[collection].rewardRates[tokenId];
        return rewardRate > 0;
    }

    // Calculate reward for the staked NFT
    function _calculateReward(
        address collection,
        uint256 tokenId,
        address staker
    ) internal view returns (uint256) {
        StakedNFT storage stakingInfo = userStakes[staker][collection][tokenId];
        uint256 rewardRate = collectionInfo[collection].rewardRates[tokenId];

        if (stakingInfo.isHardStake) {
            rewardRate *= 3; // Triple the reward rate for hard staked NFTs
        }

        uint256 timeSinceLastClaim = block.timestamp -
            stakingInfo.lastClaimedAt;
        uint256 reward = (rewardRate * timeSinceLastClaim) / DAY_IN_SECONDS;

        return stakingInfo.accumulatedReward + reward;
    }

    // Get all staked NFTs for a user
    function getAllStakedNFTs(
        address user
    ) public view returns (StakedNFT[] memory) {
        return userStakedNFTs[user];
    }

    // Get the accumulated reward for a specific staked NFT
    function getAccumulatedReward(
        address user,
        address collection,
        uint256 tokenId
    ) public view returns (uint256) {
        StakedNFT storage stakingInfo = userStakes[user][collection][tokenId];
        uint256 currentReward = _calculateReward(collection, tokenId, user);
        return stakingInfo.accumulatedReward + currentReward;
    }
}
