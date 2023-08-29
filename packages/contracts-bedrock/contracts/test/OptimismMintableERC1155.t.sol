// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { ERC1155, IERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC1155Bridge_Initializer } from "./CommonTest.t.sol";
import {
    OptimismMintableERC1155,
    IOptimismMintableERC1155
} from "../universal/OptimismMintableERC1155.sol";

contract OptimismMintableERC1155_Test is ERC1155Bridge_Initializer {
    ERC1155 internal L1Token;
    OptimismMintableERC1155 internal L2Token;

    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event TransferBatch(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256[] ids,
        uint256[] values
    );

    event Mint(address indexed account, uint256 id, uint256 value);
    event MintBatch(address indexed account, uint256[] ids, uint256[] values);

    event Burn(address indexed account, uint256 id, uint256 value);
    event BurnBatch(address indexed account, uint256[] ids, uint256[] values);

    function setUp() public override {
        super.setUp();

        // Set up the token pair.
        L1Token = new ERC1155("L1ERC1155Token");
        L2Token = new OptimismMintableERC1155(address(L2Bridge), 1, address(L1Token), "L2TokenURI");

        // Label the addresses for nice traces.
        vm.label(address(L1Token), "L1ERC1155Token");
        vm.label(address(L2Token), "L2ERC1155Token");
    }

    function test_constructor_succeeds() external {
        assertEq(L2Token.uri(0), "L2TokenURI");
        assertEq(L2Token.remoteToken(), address(L1Token));
        assertEq(L2Token.bridge(), address(L2Bridge));
        assertEq(L2Token.remoteChainId(), 1);
        assertEq(L2Token.REMOTE_TOKEN(), address(L1Token));
        assertEq(L2Token.BRIDGE(), address(L2Bridge));
        assertEq(L2Token.REMOTE_CHAIN_ID(), 1);
    }

    /// @notice Ensure that the contract supports the expected interfaces.
    function test_supportsInterfaces_succeeds() external {
        // Checks if the contract supports the IOptimismMintableERC1155 interface.
        assertTrue(L2Token.supportsInterface(type(IOptimismMintableERC1155).interfaceId));
        // Checks if the contract supports the IERC1155 interface.
        assertTrue(L2Token.supportsInterface(type(IERC1155).interfaceId));
        // Checks if the contract supports the IERC165 interface.
        assertTrue(L2Token.supportsInterface(type(IERC165).interfaceId));
    }

    function test_Mint_succeeds() external {
        // Expect a transfer event.
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(L2Bridge), address(0), alice, 1, 1);

        // Expect a mint event.
        vm.expectEmit(true, true, true, true);
        emit Mint(alice, 1, 1);

        // Mint the token.
        vm.prank(address(L2Bridge));
        L2Token.mint(alice, 1, 1);

        // Token should be owned by alice.
        assertEq(L2Token.balanceOf(alice, 1), 1);
    }

    function test_safeMint_notBridge_reverts() external {
        // Try to mint the token.
        vm.expectRevert("OptimismMintableERC1155: only bridge can call this function");
        vm.prank(address(alice));
        L2Token.mint(alice, 1, 1);
    }

    function test_burn_succeeds() external {
        // Mint the token first.
        vm.prank(address(L2Bridge));
        L2Token.mint(alice, 1, 1);

        // Expect a transfer event.
        vm.expectEmit(true, true, true, true);
        emit TransferSingle(address(L2Bridge), alice, address(0), 1, 1);

        // Expect a burn event.
        vm.expectEmit(true, true, true, true);
        emit Burn(alice, 1, 1);

        // Burn the token.
        vm.prank(address(L2Bridge));
        L2Token.burn(alice, 1, 1);

        // Token should be owned by address(0).
        assertEq(L2Token.balanceOf(alice, 1), 0);
    }

    function test_burn_notBridge_reverts() external {
        // Mint the token first.
        vm.prank(address(L2Bridge));
        L2Token.mint(alice, 1, 1);

        // Try to burn the token.
        vm.expectRevert("OptimismMintableERC1155: only bridge can call this function");
        vm.prank(address(alice));
        L2Token.burn(alice, 1, 1);
    }

    function test_tokenURI_succeeds() external {
        // Mint the token first.
        vm.prank(address(L2Bridge));
        L2Token.mint(alice, 1, 1);

        // Token URI should be correct.
        assertEq(L2Token.uri(1), "L2TokenURI");
    }
}
