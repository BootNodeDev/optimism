// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { Messenger_Initializer } from "./CommonTest.t.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// Target contract dependencies
import { L2ERC1155Bridge } from "../L2/L2ERC1155Bridge.sol";
import { OptimismMintableERC1155 } from "../universal/OptimismMintableERC1155.sol";

// Target contract
import { L1ERC1155Bridge } from "../L1/L1ERC1155Bridge.sol";

/// @dev Test ERC1155 contract.
contract TestERC1155 is ERC1155 {
    constructor() ERC1155("Test") {}

    function mint(address to, uint256 tokenId, uint256 amount) public {
        _mint(to, tokenId, amount, "");
    }
}

contract TestMintableERC1155 is OptimismMintableERC1155 {
    constructor(
        address _bridge,
        address _remoteToken
    ) OptimismMintableERC1155(_bridge, 1, _remoteToken, "Test") {}

    function mint(address to, uint256 tokenId, uint256 amount) public override {
        _mint(to, tokenId, amount, "");
    }
}

contract L1ERC1155Bridge_Test is Messenger_Initializer {
    TestERC1155 internal localToken;
    TestERC1155 internal remoteToken;

    L1ERC1155Bridge internal bridge;
    address internal constant otherBridge = address(0x3456);
    uint256 internal constant tokenId = 1;

    uint256 internal constant initialAmount = 5;
    uint256 internal constant amountBridged = 2;

    event ERC1155BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 tokenId,
        uint256 values,
        bytes extraData
    );

    event ERC1155BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 tokenId,
        uint256 values,
        bytes extraData
    );

    event ERC1155BridgeBatchInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256[] ids,
        uint256[] values,
        bytes extraData
    );

    event ERC1155BridgeBatchFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256[] ids,
        uint256[] values,
        bytes extraData
    );

    /// @dev Sets up the testing environment.
    function setUp() public override {
        super.setUp();

        // Create necessary contracts.
        bridge = new L1ERC1155Bridge(address(L1Messenger), otherBridge);
        localToken = new TestERC1155();
        remoteToken = new TestERC1155();

        // Label the bridge so we get nice traces.
        vm.label(address(bridge), "L1ERC1155Bridge");

        // Mint alice a token.
        localToken.mint(alice, tokenId, initialAmount);

        // Mint a few more for batch tests
        localToken.mint(alice, 2, initialAmount + 1);
        localToken.mint(alice, 3, initialAmount + 2);

        // Approve the bridge to transfer the token.
        vm.prank(alice);
        localToken.setApprovalForAll(address(bridge), true);
    }

    /// @dev Tests that the constructor sets the correct values.
    function test_constructor_succeeds() public {
        assertEq(address(bridge.MESSENGER()), address(L1Messenger));
        assertEq(address(bridge.OTHER_BRIDGE()), otherBridge);
        assertEq(address(bridge.messenger()), address(L1Messenger));
        assertEq(address(bridge.otherBridge()), otherBridge);
    }

    /// @dev Tests that the ERC1155 can be bridged successfully.
    function test_bridgeERC1155_succeeds() public {
        // Expect a call to the messenger.
        vm.expectCall(
            address(L1Messenger),
            abi.encodeCall(
                L1Messenger.sendMessage,
                (
                    address(otherBridge),
                    abi.encodeCall(
                        L2ERC1155Bridge.finalizeBridgeERC1155,
                        (
                            address(remoteToken),
                            address(localToken),
                            alice,
                            alice,
                            tokenId,
                            amountBridged,
                            hex"5678"
                        )
                    ),
                    1234
                )
            )
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC1155BridgeInitiated(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );

        // Bridge the token.
        vm.prank(alice);
        bridge.bridgeERC1155(
            address(localToken),
            address(remoteToken),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is locked in the bridge.
        assertEq(
            bridge.deposits(address(localToken), address(remoteToken), tokenId),
            amountBridged
        );
        assertEq(localToken.balanceOf(address(bridge), tokenId), amountBridged);
    }

    /// @dev Tests that the ERC1155 can be batch bridged successfully.
    function test_bridgeBatchERC1155_succeeds() public {
        uint256[] memory ids = new uint256[](3);
        ids[0] = tokenId;
        ids[1] = tokenId + 1;
        ids[2] = tokenId + 2;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBridged;
        amounts[1] = amountBridged + 1;
        amounts[2] = amountBridged + 2;

        // Expect a call to the messenger.
        vm.expectCall(
            address(L1Messenger),
            abi.encodeCall(
                L1Messenger.sendMessage,
                (
                    address(otherBridge),
                    abi.encodeCall(
                        L2ERC1155Bridge.finalizeBridgeBatchERC1155,
                        (
                            address(remoteToken),
                            address(localToken),
                            alice,
                            alice,
                            ids,
                            amounts,
                            hex"5678"
                        )
                    ),
                    1234
                )
            )
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC1155BridgeBatchInitiated(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            ids,
            amounts,
            hex"5678"
        );

        // Bridge the token.
        vm.prank(alice);
        bridge.bridgeBatchERC1155(
            address(localToken),
            address(remoteToken),
            ids,
            amounts,
            1234,
            hex"5678"
        );

        for (uint i = 0; i < ids.length; i++) {
            // Token is locked in the bridge.
            assertEq(
                bridge.deposits(address(localToken), address(remoteToken), ids[i]),
                amounts[i]
            );
            assertEq(localToken.balanceOf(address(bridge), ids[i]), amounts[i]);
        }
    }

    /// @dev Tests that the ERC1155 bridge reverts for non externally owned accounts.
    function test_bridgeERC1155_fromContract_reverts() external {
        // Bridge the token.
        vm.etch(alice, hex"01");
        vm.prank(alice);
        vm.expectRevert("ERC1155Bridge: account is not externally owned");
        bridge.bridgeERC1155(
            address(localToken),
            address(remoteToken),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge reverts for a zero address local token.
    function test_bridgeERC1155_localTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert();
        bridge.bridgeERC1155(
            address(0),
            address(remoteToken),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge reverts for a zero address remote token.
    function test_bridgeERC1155_remoteTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert("L1ERC1155Bridge: remote token cannot be address(0)");
        bridge.bridgeERC1155(
            address(localToken),
            address(0),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge reverts for an incorrect owner.
    function test_bridgeERC1155_wrongOwner_reverts() external {
        // Bridge the token.
        vm.prank(bob);
        vm.expectRevert("ERC1155: caller is not token owner nor approved");
        bridge.bridgeERC1155(
            address(localToken),
            address(remoteToken),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge successfully sends a token
    ///      to a different address than the owner.
    function test_bridgeERC1155To_succeeds() external {
        // Expect a call to the messenger.
        vm.expectCall(
            address(L1Messenger),
            abi.encodeCall(
                L1Messenger.sendMessage,
                (
                    address(otherBridge),
                    abi.encodeCall(
                        L2ERC1155Bridge.finalizeBridgeERC1155,
                        (
                            address(remoteToken),
                            address(localToken),
                            alice,
                            bob,
                            tokenId,
                            amountBridged,
                            hex"5678"
                        )
                    ),
                    1234
                )
            )
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC1155BridgeInitiated(
            address(localToken),
            address(remoteToken),
            alice,
            bob,
            tokenId,
            amountBridged,
            hex"5678"
        );

        // Bridge the token.
        vm.prank(alice);
        bridge.bridgeERC1155To(
            address(localToken),
            address(remoteToken),
            bob,
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is locked in the bridge.
        assertEq(
            bridge.deposits(address(localToken), address(remoteToken), tokenId),
            amountBridged
        );
        assertEq(localToken.balanceOf(address(bridge), tokenId), amountBridged);
    }

    /// @dev Tests that the ERC1155 bridge successfully sends a token
    ///      to a different address than the owner.
    function test_bridgeBatchERC1155To_succeeds() external {
        uint256[] memory ids = new uint256[](3);
        ids[0] = tokenId;
        ids[1] = tokenId + 1;
        ids[2] = tokenId + 2;

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = amountBridged;
        amounts[1] = amountBridged + 1;
        amounts[2] = amountBridged + 2;

        // Expect a call to the messenger.
        vm.expectCall(
            address(L1Messenger),
            abi.encodeCall(
                L1Messenger.sendMessage,
                (
                    address(otherBridge),
                    abi.encodeCall(
                        L2ERC1155Bridge.finalizeBridgeBatchERC1155,
                        (
                            address(remoteToken),
                            address(localToken),
                            alice,
                            bob,
                            ids,
                            amounts,
                            hex"5678"
                        )
                    ),
                    1234
                )
            )
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC1155BridgeBatchInitiated(
            address(localToken),
            address(remoteToken),
            alice,
            bob,
            ids,
            amounts,
            hex"5678"
        );

        // Bridge the token.
        vm.prank(alice);
        bridge.bridgeBatchERC1155To(
            address(localToken),
            address(remoteToken),
            bob,
            ids,
            amounts,
            1234,
            hex"5678"
        );

        for (uint i = 0; i < ids.length; i++) {
            // Token is locked in the bridge.
            assertEq(
                bridge.deposits(address(localToken), address(remoteToken), ids[i]),
                amounts[i]
            );
            assertEq(localToken.balanceOf(address(bridge), ids[i]), amounts[i]);
        }
    }

    /// @dev Tests that the ERC1155 bridge reverts for non externally owned accounts
    ///      when sending to a different address than the owner.
    function test_bridgeERC1155To_localTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert();
        bridge.bridgeERC1155To(
            address(0),
            address(remoteToken),
            bob,
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge reverts for a zero address remote token
    ///      when sending to a different address than the owner.
    function test_bridgeERC1155To_remoteTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert("L1ERC1155Bridge: remote token cannot be address(0)");
        bridge.bridgeERC1155To(
            address(localToken),
            address(0),
            bob,
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge reverts for an incorrect owner
    ////     when sending to a different address than the owner.
    function test_bridgeERC1155To_wrongOwner_reverts() external {
        // Bridge the token.
        vm.prank(bob);
        vm.expectRevert("ERC1155: caller is not token owner nor approved");
        bridge.bridgeERC1155To(
            address(localToken),
            address(remoteToken),
            bob,
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge successfully finalizes a withdrawal.
    function test_finalizeBridgeERC1155_succeeds() external {
        // Bridge the token.
        vm.prank(alice);
        bridge.bridgeERC1155(
            address(localToken),
            address(remoteToken),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Expect an event to be emitted.
        vm.expectEmit(true, true, true, true);
        emit ERC1155BridgeFinalized(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );

        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(otherBridge)
        );
        vm.prank(address(L1Messenger));
        bridge.finalizeBridgeERC1155(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(bridge.deposits(address(localToken), address(remoteToken), tokenId), 0);
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that the ERC1155 bridge finalize reverts when not called
    ///      by the remote bridge.
    function test_finalizeBridgeERC1155_notViaLocalMessenger_reverts() external {
        // Finalize a withdrawal.
        vm.prank(alice);
        vm.expectRevert("ERC1155Bridge: function can only be called from the other bridge");
        bridge.finalizeBridgeERC1155(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );
    }

    /// @dev Tests that the ERC1155 bridge finalize reverts when not called
    ///      from the remote messenger.
    function test_finalizeBridgeERC1155_notFromRemoteMessenger_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(alice)
        );
        vm.prank(address(L1Messenger));
        vm.expectRevert("ERC1155Bridge: function can only be called from the other bridge");
        bridge.finalizeBridgeERC1155(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );
    }

    /// @dev Tests that the ERC1155 bridge finalize reverts when the local token
    ///      is set as the bridge itself.
    function test_finalizeBridgeERC1155_selfToken_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(otherBridge)
        );
        vm.prank(address(L1Messenger));
        vm.expectRevert("L1ERC1155Bridge: local token cannot be self");
        bridge.finalizeBridgeERC1155(
            address(bridge),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );
    }

    /// @dev Tests that the ERC1155 bridge finalize reverts when the remote token
    ///      is not escrowed in the L1 bridge.
    function test_finalizeBridgeERC1155_notEscrowed_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L1Messenger),
            abi.encodeWithSelector(L1Messenger.xDomainMessageSender.selector),
            abi.encode(otherBridge)
        );
        vm.prank(address(L1Messenger));
        vm.expectRevert();
        bridge.finalizeBridgeERC1155(
            address(localToken),
            address(remoteToken),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );
    }
}
