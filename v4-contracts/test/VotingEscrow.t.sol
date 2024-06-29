// 1:1 with Hardhat test
pragma solidity 0.8.13;

import './BaseTest.sol';

contract VotingEscrowTest is BaseTest {
    VotingEscrow escrow;

    function setUp() public {
        deployOwners();
        deployCoins();
        mintStables();
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e21;
        mintFlow(owners, amounts);

        VeArtProxy artProxy = new VeArtProxy();

        deployPairFactoryAndRouter();
        deployMainPairWithOwner(address(owner));

        escrow = new VotingEscrow(address(FLOW), address(flowDaiPair),address(artProxy), owners[0]);
    }

    function testCreateLock() public {
        flowDaiPair.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week

        // Balance should be zero before and 1 after creating the lock
        assertEq(escrow.balanceOf(address(owner)), 0);
        escrow.create_lock(TOKEN_1, lockDuration);
        assertEq(escrow.currentTokenId(), 1);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);
    }

    function testCreateLockAndMaxLock() public {
        flowDaiPair.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week

        // Balance should be zero before and 1 after creating the lock
        assertEq(escrow.balanceOf(address(owner)), 0);
        escrow.create_lock(TOKEN_1, lockDuration);
        assertEq(escrow.currentTokenId(), 1);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);
        
        escrow.max_lock(1);

        int amount;
        uint duration;
        (amount, duration) = escrow.locked(1);
        assertEq(duration, lockDuration);

        escrow.enable_max_lock(1);

        escrow.isApprovedOrOwner(address(owner),1);

        (amount, duration) = escrow.locked(1);
        assertEq(duration, 52 * 7 * 86400);

        escrow.max_lock(1);

        escrow.disable_max_lock(1);
    }

     function testCreateLockAndMaxLock2() public {
        flowDaiPair.approve(address(escrow), TOKEN_1*2);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week

        // Balance should be zero before and 1 after creating the lock
        assertEq(escrow.balanceOf(address(owner)), 0);
        escrow.create_lock(TOKEN_1, lockDuration);
        escrow.create_lock(TOKEN_1, lockDuration);
        assertEq(escrow.currentTokenId(), 2);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 2);
        
        escrow.max_lock(1);
        escrow.max_lock(2);

        int amount;
        uint duration;
        (amount, duration) = escrow.locked(1);
        assertEq(duration, lockDuration);

        escrow.enable_max_lock(1);
        escrow.enable_max_lock(2);

        escrow.isApprovedOrOwner(address(owner),1);

        (amount, duration) = escrow.locked(1);
        assertEq(duration, 52 * 7 * 86400);

        assertEq(escrow.maxLockIdToIndex(1),1);
        assertEq(escrow.maxLockIdToIndex(2),2);
        
        escrow.disable_max_lock(1);
        escrow.disable_max_lock(2);
     }

    function testSplit() public {
        flowDaiPair.approve(address(escrow), 10*TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.create_lock(10*TOKEN_1, lockDuration);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 3*TOKEN_1;
        amounts[1] = 7*TOKEN_1;

        int amount;
        uint duration;
        (amount, duration) = escrow.locked(1);
        assertEq(amount, 10e18);
        assertEq(duration, lockDuration);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);

        escrow.split(1,amounts[1]);

        (amount, duration) = escrow.locked(1);
        assertEq(amount, 3e18);
        assertEq(duration, lockDuration);
        assertEq(escrow.ownerOf(1), address(owner));

        (amount, duration) = escrow.locked(2);
        assertEq(amount, 7e18);
        assertEq(duration, lockDuration);
        assertEq(escrow.ownerOf(2), address(owner));

        assertEq(escrow.balanceOf(address(owner)), 2);
    }

    function testSplitBlock() public {
        flowDaiPair.approve(address(escrow), 10*TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.create_lock(10*TOKEN_1, lockDuration);

        uint[] memory amounts = new uint[](2);
        amounts[0] = 3*TOKEN_1;
        amounts[1] = 7*TOKEN_1;

        int amount;
        uint duration;
        (amount, duration) = escrow.locked(1);
        assertEq(amount, 10e18);
        assertEq(duration, lockDuration);
        assertEq(escrow.ownerOf(1), address(owner));
        assertEq(escrow.balanceOf(address(owner)), 1);

        escrow.block_split(1);

        vm.expectRevert("split blocked");
        escrow.split(1,amounts[1]);

        escrow.transferFrom(address(owner),address(owner2),1);

        vm.startPrank(address(owner2));
        escrow.split(1,amounts[1]);

        (amount, duration) = escrow.locked(1);
        assertEq(amount, 3e18);
        assertEq(duration, lockDuration);
        assertEq(escrow.ownerOf(1), address(owner2));

        (amount, duration) = escrow.locked(2);
        assertEq(amount, 7e18);
        assertEq(duration, lockDuration);
        assertEq(escrow.ownerOf(2), address(owner2));

        assertEq(escrow.balanceOf(address(owner2)), 2);
    }

    function testCreateLockOutsideAllowedZones() public {
        flowDaiPair.approve(address(escrow), 1e21);
        vm.expectRevert(abi.encodePacked('Voting lock can be 52 weeks max'));
        escrow.create_lock(1e21, FIFTY_TWO_WEEKS + ONE_WEEK);
    }

    function testWithdraw() public {

        uint flowDaiPairBalance = flowDaiPair.balanceOf(address(owner));
        flowDaiPair.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.create_lock(TOKEN_1, lockDuration);

        // Try withdraw early
        uint256 tokenId = 1;
        vm.expectRevert(abi.encodePacked("The lock didn't expire"));
        escrow.withdraw(tokenId);
        // Now try withdraw after the time has expired
        vm.warp(block.timestamp + lockDuration);
        vm.roll(block.number + 1); // mine the next block
        escrow.withdraw(tokenId);

        assertEq(flowDaiPair.balanceOf(address(owner)), flowDaiPairBalance);
        // Check that the NFT is burnt
        assertEq(escrow.balanceOfNFT(tokenId), 0);
        assertEq(escrow.ownerOf(tokenId), address(0));
    }

    function testCheckTokenURICalls() public {
        // tokenURI should not work for non-existent token ids
        vm.expectRevert(abi.encodePacked("Query for nonexistent token"));
        escrow.tokenURI(999);
        flowDaiPair.approve(address(escrow), TOKEN_1);
        uint256 lockDuration = 7 * 24 * 3600; // 1 week
        escrow.create_lock(TOKEN_1, lockDuration);

        uint256 tokenId = 1;
        vm.warp(block.timestamp + lockDuration);
        vm.roll(block.number + 1); // mine the next block

        // Just check that this doesn't revert
        escrow.tokenURI(tokenId);

        // Withdraw, which destroys the NFT
        escrow.withdraw(tokenId);

        // tokenURI should not work for this anymore as the NFT is burnt
        vm.expectRevert(abi.encodePacked("Query for nonexistent token"));
        escrow.tokenURI(tokenId);
    }

    function testConfirmSupportsInterfaceWorksWithAssertedInterfaces() public {
        // Check that it supports all the asserted interfaces.
        bytes4 ERC165_INTERFACE_ID = 0x01ffc9a7;
        bytes4 ERC721_INTERFACE_ID = 0x80ac58cd;
        bytes4 ERC721_METADATA_INTERFACE_ID = 0x5b5e139f;

        assertTrue(escrow.supportsInterface(ERC165_INTERFACE_ID));
        assertTrue(escrow.supportsInterface(ERC721_INTERFACE_ID));
        assertTrue(escrow.supportsInterface(ERC721_METADATA_INTERFACE_ID));
    }

    function testCheckSupportsInterfaceHandlesUnsupportedInterfacesCorrectly() public {
        bytes4 ERC721_FAKE = 0x780e9d61;
        assertFalse(escrow.supportsInterface(ERC721_FAKE));
    }
}
