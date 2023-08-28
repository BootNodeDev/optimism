// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// Testing utilities
import { Messenger_Initializer } from "./CommonTest.t.sol";

// Target contract dependencies
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { L1ERC1155Bridge } from "../L1/L1ERC1155Bridge.sol";
import { OptimismMintableERC1155 } from "../universal/OptimismMintableERC1155.sol";

// Target contract
import { L2ERC1155Bridge } from "../L2/L2ERC1155Bridge.sol";

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

contract L2ERC1155Bridge_Test is Messenger_Initializer {
    TestMintableERC1155 internal localToken;
    TestERC1155 internal remoteToken;
    L2ERC1155Bridge internal bridge;
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

    /// @dev Sets up the test suite.
    function setUp() public override {
        super.setUp();

        // Create necessary contracts.
        bridge = new L2ERC1155Bridge(address(L2Messenger), otherBridge);
        remoteToken = new TestERC1155();
        localToken = new TestMintableERC1155(address(bridge), address(remoteToken));

        // Label the bridge so we get nice traces.
        vm.label(address(bridge), "L2ERC1155Bridge");

        // Mint alice a token.
        localToken.mint(alice, tokenId, initialAmount);

        // Approve the bridge to transfer the token.
        vm.prank(alice);
        localToken.setApprovalForAll(address(bridge), true);
    }

    /// @dev Tests that the constructor sets the correct variables.
    function test_constructor_succeeds() public {
        assertEq(address(bridge.MESSENGER()), address(L2Messenger));
        assertEq(address(bridge.OTHER_BRIDGE()), otherBridge);
        assertEq(address(bridge.messenger()), address(L2Messenger));
        assertEq(address(bridge.otherBridge()), otherBridge);
    }

    /// @dev Tests that `bridgeERC1155` correctly bridges a token and
    ///      burns it on the origin chain.
    function test_bridgeERC1155_succeeds() public {
        // Expect a call to the messenger.
        vm.expectCall(
            address(L2Messenger),
            abi.encodeCall(
                L2Messenger.sendMessage,
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

        // Token is burned. Amount was started with 5
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount - amountBridged);
    }

    /// @dev Tests that `bridgeERC1155` reverts if the owner is not an EOA.
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
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `bridgeERC1155` reverts if the local token is the zero address.
    function test_bridgeERC1155_localTokenZeroAddress_reverts() external {
        // Bridge the token by an amount of 2.
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

        // Token is not locked in the bridge. The amount is the original one
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `bridgeERC1155` reverts if the remote token is the zero address.
    function test_bridgeERC1155_remoteTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert("L2ERC1155Bridge: remote token cannot be address(0)");
        bridge.bridgeERC1155(
            address(localToken),
            address(0),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `bridgeERC1155` reverts if the caller is not the token owner.
    function test_bridgeERC1155_wrongOwner_reverts() external {
        // Bridge the token.
        vm.prank(bob);
        vm.expectRevert("ERC1155: burn amount exceeds balance");
        bridge.bridgeERC1155(
            address(localToken),
            address(remoteToken),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `bridgeERC1155To` correctly bridges a token
    ///      and burns it on the origin chain.
    function test_bridgeERC1155To_succeeds() external {
        // Expect a call to the messenger.
        vm.expectCall(
            address(L2Messenger),
            abi.encodeCall(
                L2Messenger.sendMessage,
                (
                    address(otherBridge),
                    abi.encodeCall(
                        L1ERC1155Bridge.finalizeBridgeERC1155,
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

        // Token is burned.
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount - amountBridged);
    }

    /// @dev Tests that `bridgeERC1155To` reverts if the local token is the zero address.
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
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `bridgeERC1155To` reverts if the remote token is the zero address.
    function test_bridgeERC1155To_remoteTokenZeroAddress_reverts() external {
        // Bridge the token.
        vm.prank(alice);
        vm.expectRevert("L2ERC1155Bridge: remote token cannot be address(0)");
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
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `bridgeERC1155To` reverts if the caller is not the token owner.
    function test_bridgeERC1155To_wrongOwner_reverts() external {
        // Bridge the token.
        vm.prank(bob);
        vm.expectRevert("ERC1155: burn amount exceeds balance");
        bridge.bridgeERC1155To(
            address(localToken),
            address(remoteToken),
            bob,
            tokenId,
            initialAmount,
            1234,
            hex"5678"
        );

        // Token is not locked in the bridge.
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
    }

    /// @dev Tests that `finalizeBridgeERC1155` correctly finalizes a bridged token.
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
            address(L2Messenger),
            abi.encodeWithSelector(L2Messenger.xDomainMessageSender.selector),
            abi.encode(otherBridge)
        );
        vm.prank(address(L2Messenger));
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
        assertEq(localToken.balanceOf(alice, tokenId), initialAmount);
        assertEq(remoteToken.balanceOf(alice, tokenId), 0);
    }

    /// @dev Tests that `finalizeBridgeERC1155` reverts if the token is not compliant
    ///      with the `IOptimismMintableERC1155` interface.
    function test_finalizeBridgeERC1155_interfaceNotCompliant_reverts() external {
        // Create a non-compliant token
        NonCompliantERC1155 nonCompliantToken = new NonCompliantERC1155("");

        // Bridge the non-compliant token.
        vm.prank(alice);
        bridge.bridgeERC1155(
            address(nonCompliantToken),
            address(0x01),
            tokenId,
            amountBridged,
            1234,
            hex"5678"
        );

        // Attempt to finalize the withdrawal. Should revert because the token does not claim
        // to be compliant with the `IOptimismMintableERC1155` interface.
        vm.mockCall(
            address(L2Messenger),
            abi.encodeWithSelector(L2Messenger.xDomainMessageSender.selector),
            abi.encode(otherBridge)
        );
        vm.prank(address(L2Messenger));
        vm.expectRevert("L2ERC1155Bridge: local token interface is not compliant");
        bridge.finalizeBridgeERC1155(
            address(address(nonCompliantToken)),
            address(address(0x01)),
            alice,
            alice,
            tokenId,
            amountBridged,
            hex"5678"
        );
    }

    /// @dev Tests that `finalizeBridgeERC1155` reverts when not called by the remote bridge.
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

    /// @dev Tests that `finalizeBridgeERC1155` reverts when not called by the remote bridge.
    function test_finalizeBridgeERC1155_notFromRemoteMessenger_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L2Messenger),
            abi.encodeWithSelector(L2Messenger.xDomainMessageSender.selector),
            abi.encode(alice)
        );
        vm.prank(address(L2Messenger));
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

    /// @dev Tests that `finalizeBridgeERC1155` reverts when the local token is the
    ///      address of the bridge itself.
    function test_finalizeBridgeERC1155_selfToken_reverts() external {
        // Finalize a withdrawal.
        vm.mockCall(
            address(L2Messenger),
            abi.encodeWithSelector(L2Messenger.xDomainMessageSender.selector),
            abi.encode(otherBridge)
        );
        vm.prank(address(L2Messenger));
        vm.expectRevert("L2ERC1155Bridge: local token cannot be self");
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
}

/// @dev A non-compliant ERC1155 token that does not implement the full ERC1155 interface.
///      This is used to test that the bridge will revert if the token does not claim to
///      support the ERC1155 interface.
contract NonCompliantERC1155 {
    mapping(uint256 => mapping(address => uint256)) private _balances;
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    string private _uri;

    constructor(string memory uri_) {
        _uri = uri_;
    }

    function burn(address _to, uint256 _id, uint256 _amount) external {}

    function burnBatch(address _from, uint256[] memory _ids, uint256[] memory _amounts) external {}

    function mint(address _to, uint256 _id, uint256 _amount) external {}

    function mintBatch(address _to, uint256[] memory _ids, uint256[] memory _amounts) external {
        // Do nothing.
    }

    function remoteToken() external pure returns (address) {
        return address(0x01);
    }

    function uri(uint256) public view returns (string memory) {
        return _uri;
    }

    function balanceOf(address account, uint256 id) public view returns (uint256) {}

    function balanceOfBatch(
        address[] memory accounts,
        uint256[] memory ids
    ) public view returns (uint256[] memory) {}

    function supportsInterface(bytes4) external pure returns (bool) {
        return false;
    }
}
