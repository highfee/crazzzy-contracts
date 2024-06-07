// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

contract NFTRaffle is ReentrancyGuard, ERC721Holder, Ownable {
    // state variables;
    using SafeERC20 for IERC20;

    IERC721 mapNFT;

    uint256 public raffleIdCounter;
    uint256[] public activeRaffleIDs;

    address[] public whitelist;
    mapping(address => bool) public isWhitelisted;

    struct Raffle {
        address NFTAddress;
        uint256 tokenId;
        uint256 maxTicketPerUser;
        uint256 totalTicketsSold;
        address[] players; // to keep track of all the players
        address[] playerSelector; // to keep track of all tickets bought per users
        uint256 entryCost;
        uint256 raffleId;
        uint256 maxTickets; // total supply of tickets for the raffle
        uint256 endTimestamp;
        address winner;
        bool raffleStatus;
        address creator;
    }

    Raffle[] public raffles;

    // mapping(uint256 => Raffle) public raffles;

    event NFTPrizeClaimed(uint256 indexed raffleId, address indexed winner);
    event RaffleCreated(uint256 indexed raffleId);
    event NewEntry(
        uint256 indexed raffleId,
        address indexed participant,
        uint256 numberOfTickets
    );
    event RaffleEnded(
        uint256 indexed raffleId,
        address indexed winner,
        uint256 totalTicketsSold
    );

    // constructor(address _mapNFTAddress) Ownable(msg.sender) {
    //     mapNFT = IERC721(_mapNFTAddress); // this set the contract address of the map nft

    //     addToWhitelist(msg.sender); // Add owner to the whitelist
    // }
    constructor() Ownable(msg.sender) {
        addToWhitelist(msg.sender); // Add owner to the whitelist
    }

    modifier onlyWhitelisted() {
        require(isWhitelisted[msg.sender], "Address is not whitelisted");
        _;
    }

    function addToWhitelist(address _address) public onlyOwner {
        require(!isWhitelisted[_address], "Address already whitelisted");
        whitelist.push(_address);
        isWhitelisted[_address] = true;
    }

    function transferNFT(
        address _nftAddress,
        uint256 _tokenId,
        address _from,
        address _to
    ) private onlyOwner {
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _from,
            "Not owner of NFT"
        );

        IERC721(_nftAddress).safeTransferFrom(_from, _to, _tokenId, "");
    }

    // set map nft

    function setMapNFT(address _address) public onlyOwner {
        mapNFT = IERC721(_address);
    }

    // check if buyer have reach max buy

    function hasExceededMaxTickets(
        uint256 raffleId,
        uint256 _numOfTickets
    ) internal view returns (bool) {
        Raffle storage raffle = raffles[raffleId];
        uint256 count = 0;
        for (uint256 i = 0; i < raffle.playerSelector.length; i++) {
            if (raffle.playerSelector[i] == msg.sender) {
                count++;
            }
        }
        return count + _numOfTickets > raffle.maxTicketPerUser;
    }

    // create raffle

    function createRaffle(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _maxTicketsPerUser,
        uint256 _endTimestamp,
        uint256 _entryCost,
        uint256 _maxTickets
    ) public onlyWhitelisted {
        // check if the end time provided is not in the past
        require(
            _endTimestamp > block.timestamp,
            "End timestamp must be in the future"
        );

        uint256 raffleId = raffleIdCounter;

        Raffle memory newRaffle = Raffle({
            NFTAddress: _nftAddress,
            tokenId: _tokenId,
            maxTicketPerUser: _maxTicketsPerUser,
            totalTicketsSold: 0,
            players: new address[](0),
            playerSelector: new address[](0),
            entryCost: _entryCost,
            raffleId: raffleId,
            maxTickets: _maxTickets,
            endTimestamp: _endTimestamp,
            winner: address(0),
            raffleStatus: true,
            creator: msg.sender
        });

        transferNFT(_nftAddress, _tokenId, msg.sender, address(this));

        activeRaffleIDs.push(raffleId);

        raffles.push(newRaffle);

        raffleIdCounter += 1;

        emit RaffleCreated(raffleId);
    }

    // join raffle

    function joinRaffle(uint256 raffleId, uint256 numOfTickets) internal {
        Raffle storage raffle = raffles[raffleId];
        require(
            block.timestamp < raffle.endTimestamp && raffle.raffleStatus,
            "Ended"
        );
        require(
            numOfTickets <= raffle.maxTicketPerUser,
            "You are exceeding the max number of tickets buyable for a user"
        );
        require(
            numOfTickets > 0,
            "ticket to be bought should be greater than 0"
        );
        require(
            numOfTickets + raffle.totalTicketsSold < raffle.maxTickets,
            "Sold out"
        );

        require(
            !hasExceededMaxTickets(raffleId, numOfTickets),
            "You are exceeding the max number of tickets buyable for a user"
        );

        for (uint256 i = 0; i < numOfTickets; i++) {
            raffle.totalTicketsSold++;
            raffle.playerSelector.push(msg.sender);
        }

        emit NewEntry(raffleId, msg.sender, numOfTickets);
    }

    function buyRaffleWithNativeToken(
        uint256 _raffleId,
        uint256 _numOfTickets
    ) public payable nonReentrant {
        Raffle storage raffle = raffles[_raffleId];

        require(
            msg.value >= _numOfTickets * raffle.entryCost,
            "Insufficient funds"
        );

        joinRaffle(_raffleId, _numOfTickets);

        bool alreadyIncluded = false;

        for (uint256 i = 0; i < raffle.players.length; i++) {
            if (raffle.players[i] == msg.sender) {
                alreadyIncluded = true;
                break;
            }
        }
        if (!alreadyIncluded) {
            raffle.players.push(msg.sender);
        }
    }

    function buyRaffleWithERC20Token(
        address _token,
        uint256 _raffleId,
        uint256 _numOfTickets
    ) public nonReentrant {
        Raffle storage raffle = raffles[_raffleId];
        // require(msg.value == 0, "Ether is not accepted for this transaction");
        require(
            IERC20(_token).allowance(msg.sender, address(this)) >=
                raffle.entryCost * _numOfTickets,
            "Insufficient allowance"
        );

        joinRaffle(_raffleId, _numOfTickets);

        IERC20(_token).safeTransferFrom(
            msg.sender,
            address(this),
            raffle.entryCost * _numOfTickets
        );
        bool alreadyIncluded = false;

        for (uint256 i = 0; i < raffle.players.length; i++) {
            if (raffle.players[i] == msg.sender) {
                alreadyIncluded = true;
                break;
            }
        }
        if (!alreadyIncluded) {
            raffle.players.push(msg.sender);
        }
    }

    function freeRaffleForMapNFTHolder(
        uint256 _raffleId,
        uint256 _numOfTickets
    ) public nonReentrant {
        require(address(mapNFT) != address(0), "Map NFT address is not set");

        require(mapNFT.balanceOf(msg.sender) > 0, "No map NFT");

        Raffle storage raffle = raffles[_raffleId];

        joinRaffle(_raffleId, _numOfTickets);

        bool alreadyIncluded = false;

        for (uint256 i = 0; i < raffle.players.length; i++) {
            if (raffle.players[i] == msg.sender) {
                alreadyIncluded = true;
                break;
            }
        }
        if (!alreadyIncluded) {
            raffle.players.push(msg.sender);
        }
    }

    function selectWinner(uint256 _raffleId) public nonReentrant onlyOwner {
        Raffle storage raffle = raffles[_raffleId];

        require(raffle.playerSelector.length > 0, "No Player in the raffle");
        require(raffle.NFTAddress != address(0), "NFT Prize not set");

        uint256 winnerIndex = random(_raffleId) % raffle.playerSelector.length;
        address winner = raffle.playerSelector[winnerIndex];

        raffle.winner = winner;
    }

    function random(uint256 _raffleId) private view returns (uint256) {
        Raffle storage raffle = raffles[_raffleId];
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        blockhash(block.number - 1),
                        block.timestamp,
                        raffle.players.length
                    )
                )
            );
    }

    function getMapNFTBal(address _address) public view returns (uint256) {
        return mapNFT.balanceOf(_address);
    }

    function endRaffle(uint256 _raffleId) public {
        Raffle storage raffle = raffles[_raffleId];

        require(raffle.raffleStatus, "raffle already ended");

        require(raffle.creator == msg.sender, "Not creator of raffle");
        // require(
        //     raffle.endTimestamp >= block.timestamp,
        //     "raffle has not yet ended"
        // );
        raffle.endTimestamp = block.timestamp;
        raffle.raffleStatus = false;
    }

    function CheckRaffleStatus(uint256 _raffleId) public view returns (bool) {
        Raffle storage raffle = raffles[_raffleId];
        return raffle.raffleStatus;
    }

    function ClaimNFTPrizeReward(uint256 _raffleId) public {
        Raffle storage raffle = raffles[_raffleId];

        // Ensure that the raffle has ended
        require(
            block.timestamp >= raffle.endTimestamp,
            "Raffle has not ended yet"
        );

        // Ensure that the caller is one of the winners
        require(raffle.players.length > 0, "No winners in the raffle");
        require(msg.sender == raffle.winner, "not a winner");

        // Perform actions to transfer the NFT prize to the caller
        // For example:
        transferNFT(
            raffle.NFTAddress,
            raffle.tokenId,
            address(this),
            msg.sender
        );

        // Emit event to indicate successful claim of NFT prize
        emit NFTPrizeClaimed(_raffleId, msg.sender);
    }

    function checkContractBal(address _token) public view returns (uint256) {
        require(address(_token) != address(0), "Token address not set");
        return IERC20(_token).balanceOf(address(this));
    }

    function withdrawContractBal(
        address _token,
        uint256 _amount
    ) public onlyOwner {
        require(_token != address(0), "Token address cannot be zero");
        return IERC20(_token).safeTransfer(address(this), _amount);
    }

    function getAllRaffles() public view returns (Raffle[] memory) {
        return raffles;
    }

    function getRaffleDetails(
        uint256 _raffleId
    )
        public
        view
        returns (
            address NFTAddress,
            uint256 tokenId,
            uint256 maxTicketPerUser,
            uint256 totalTicketsSold,
            address[] memory players, // to keep track of all the players
            address[] memory playerSelector, // to keep track of all tickets bought per users
            uint256 entryCost,
            uint256 raffleId,
            uint256 maxTickets, // total supply of tickets for the raffle
            uint256 endTimestamp,
            address winner,
            bool raffleStatus,
            address creator
        )
    {
        require(_raffleId <= raffleIdCounter, "Invalid raffle ID");

        Raffle storage raffle = raffles[_raffleId];

        return (
            raffle.NFTAddress,
            raffle.tokenId,
            raffle.maxTicketPerUser,
            raffle.totalTicketsSold,
            raffle.players,
            raffle.playerSelector,
            raffle.entryCost,
            raffle.raffleId,
            raffle.maxTickets,
            raffle.endTimestamp,
            raffle.winner,
            raffle.raffleStatus,
            raffle.creator
        );
    }
}
