// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from 'forge-std/Test.sol';
import {RandomVDFv1} from '../../contracts/examples/RandomVDFv1.sol';
import {SlothReference} from './helpers/SlothReference.sol';

contract RandomVDFv1Test is Test {
    RandomVDFv1 app;
    uint256 constant PRIME = 2 ** 256 - 189;
    bytes32 constant ENTROPY = keccak256('future block');
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    function setUp() public {
        vm.roll(100);
        app = new RandomVDFv1(3);
    }

    function _request(address actor) private returns (uint256 target) {
        vm.prank(actor);
        app.createSeed();
        return app.seedBlocks(actor);
    }

    function _finalize(address actor, uint256 target) private returns (uint256 seed) {
        vm.roll(target + 1);
        vm.setBlockhash(target, ENTROPY);
        vm.prank(actor);
        app.finalizeSeed();
        return app.seeds(actor);
    }

    function test_ConstructorAndInitialState() public {
        assertEq(app.prime(), PRIME);
        assertEq(app.iterations(), 3);
        assertEq(app.proof(), 0);
        assertFalse(app.proven());
        vm.expectRevert(RandomVDFv1.InvalidIterations.selector);
        new RandomVDFv1(0);
        assertEq((new RandomVDFv1(type(uint256).max)).iterations(), type(uint256).max);
    }

    function test_CommitUsesFutureBlockAndCannotBeReplaced() public {
        uint256 target = _request(ALICE);
        assertEq(target, block.number + 1);
        assertEq(app.seeds(ALICE), 0);
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedAlreadyCreated.selector);
        app.createSeed();
        assertEq(app.seedBlocks(ALICE), target);
    }

    function test_RequiresRequestCompletedBlockAndAvailableHash() public {
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedNotReady.selector);
        app.finalizeSeed();
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedNotReady.selector);
        app.prove(0);
        uint256 target = _request(ALICE);
        vm.roll(target);
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedNotReady.selector);
        app.finalizeSeed();
        vm.roll(target + 1);
        vm.setBlockhash(target, bytes32(0));
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedNotReady.selector);
        app.finalizeSeed();
    }

    function test_SeedMatchesDomainAndRemainsLocked() public {
        uint256 target = _request(ALICE);
        uint256 seed = _finalize(ALICE, target);
        assertEq(
            seed, 1 + uint256(keccak256(abi.encode(address(app), block.chainid, ALICE, target, ENTROPY))) % (PRIME - 1)
        );
        assertGt(seed, 0);
        assertLt(seed, PRIME);
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedAlreadyCreated.selector);
        app.finalizeSeed();
        vm.roll(target + 257);
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.SeedAlreadyCreated.selector);
        app.createSeed();
        assertEq(app.seeds(ALICE), seed);
    }

    function test_FinalizationDeadlineAndExpiredRequestRestart() public {
        uint256 target = _request(ALICE);
        vm.roll(target + 256);
        vm.setBlockhash(target, ENTROPY);
        vm.prank(ALICE);
        app.finalizeSeed();
        assertGt(app.seeds(ALICE), 0);
        target = _request(BOB);
        vm.roll(target + 257);
        vm.prank(BOB);
        vm.expectRevert(RandomVDFv1.SeedExpired.selector);
        app.finalizeSeed();
        vm.prank(BOB);
        app.createSeed();
        assertEq(app.seedBlocks(BOB), block.number + 1);
        assertEq(app.seeds(BOB), 0);
    }

    function test_ProofRequiresCorrectSenderAndCanonicalValue() public {
        uint256 target = _request(ALICE);
        uint256 seed = _finalize(ALICE, target);
        uint256 proof = SlothReference.compute(seed, PRIME, 3);
        vm.prank(BOB);
        vm.expectRevert(RandomVDFv1.SeedNotReady.selector);
        app.prove(proof);
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.InvalidProof.selector);
        app.prove(0);
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.InvalidProof.selector);
        app.prove(PRIME);
        uint256 bobTarget = _request(BOB);
        _finalize(BOB, bobTarget);
        vm.prank(BOB);
        vm.expectRevert(RandomVDFv1.InvalidProof.selector);
        app.prove(proof);
        vm.prank(ALICE);
        app.prove(proof);
        assertEq(app.proof(), proof);
        assertTrue(app.proven());
        vm.prank(ALICE);
        vm.expectRevert(RandomVDFv1.AlreadyProven.selector);
        app.prove(proof);
        vm.prank(BOB);
        vm.expectRevert(RandomVDFv1.AlreadyProven.selector);
        app.createSeed();
        vm.prank(BOB);
        vm.expectRevert(RandomVDFv1.AlreadyProven.selector);
        app.finalizeSeed();
        assertEq(app.proof(), proof);
    }

    function test_DoesNotAcceptEth() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool success,) = address(app).call{value: 1}(abi.encodeCall(app.createSeed, ()));
        assertFalse(success);
        assertEq(address(app).balance, 0);
    }

    function testFuzz_SeedBindingAndCompleteLifecycle(address actor, bytes32 entropy, uint8 wait) public {
        vm.assume(actor != address(0));
        vm.assume(entropy != bytes32(0));
        uint256 target = _request(actor);
        vm.roll(target + 1 + uint256(wait));
        vm.setBlockhash(target, entropy);
        vm.prank(actor);
        app.finalizeSeed();
        uint256 expected =
            1 + uint256(keccak256(abi.encode(address(app), block.chainid, actor, target, entropy))) % (PRIME - 1);
        assertEq(app.seeds(actor), expected);
        uint256 proof = SlothReference.compute(expected, PRIME, 3);
        vm.prank(actor);
        app.prove(proof);
        assertEq(app.proof(), proof);
        assertTrue(app.proven());
    }
}
